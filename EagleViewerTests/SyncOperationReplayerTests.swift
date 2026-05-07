//
//  SyncOperationReplayerTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import Foundation
import XCTest
@testable import EagleViewer

final class SyncOperationReplayerTests: XCTestCase {
    func test_replayPendingOperations_withUpdateItem_shouldApplyAndRemoveOperation() async throws {
        // Arrange
        let queue = InMemorySyncOperationQueue()
        let issueStore = InMemorySyncIssueStore()
        let operation = try updateOperation()
        await queue.seed([operation])
        let transport = SequentialEagleAPITransport(responses: [
            Data(#"{"status":"success"}"#.utf8),
        ])
        let client = EagleAPIClient(configuration: .localhost(), transport: transport)
        let replayer = SyncOperationReplayer(queue: queue, issueStore: issueStore, apiClient: client)

        // Act
        let result = try await replayer.replayPendingOperations(for: operation.libraryId)

        // Assert
        let operations = await queue.operations
        let requests = await transport.requests
        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.conflictedCount, 0)
        XCTAssertTrue(operations.isEmpty)
        XCTAssertEqual(requests.first?.url?.path, "/api/v2/item/update")
    }

    func test_replayPendingOperations_withServerNewerThanBaseline_shouldMarkOperationConflicted() async throws {
        // Arrange
        let queue = InMemorySyncOperationQueue()
        let issueStore = InMemorySyncIssueStore()
        let operation = try updateOperation(baselineModificationTime: 100)
        await queue.seed([operation])
        let transport = SequentialEagleAPITransport(responses: [
            Data("""
            {
              "status": "success",
              "data": {
                "data": [{ "id": "ITEM-A", "modificationTime": 200 }],
                "total": 1,
                "offset": 0,
                "limit": 1
              }
            }
            """.utf8),
        ])
        let client = EagleAPIClient(configuration: .localhost(), transport: transport)
        let replayer = SyncOperationReplayer(queue: queue, issueStore: issueStore, apiClient: client)

        // Act
        let result = try await replayer.replayPendingOperations(for: operation.libraryId)

        // Assert
        let operations = await queue.operations
        let issues = await issueStore.issues
        XCTAssertEqual(result.appliedCount, 0)
        XCTAssertEqual(result.conflictedCount, 1)
        XCTAssertEqual(operations.first?.state, .conflicted)
        XCTAssertEqual(issues.first?.category, .conflict)
    }

    private func updateOperation(baselineModificationTime: Int64? = nil) throws -> SyncOperation {
        let payload = try SyncOperationEncoder().encodeUpdateItem(EagleItemUpdateRequest(
            id: "ITEM-A",
            tags: ["reviewed"],
            star: 5
        ))

        return SyncOperation(
            libraryId: 1,
            itemId: "ITEM-A",
            kind: .updateItem,
            payload: payload,
            baselineModificationTime: baselineModificationTime
        )
    }
}

private actor InMemorySyncOperationQueue: SyncOperationQueue {
    private(set) var operations: [SyncOperation] = []

    func seed(_ operations: [SyncOperation]) {
        self.operations = operations
    }

    func enqueue(_ operation: SyncOperation) async throws {
        operations.append(operation)
    }

    func pendingOperations(for libraryId: Int64) async throws -> [SyncOperation] {
        operations.filter { operation in
            operation.libraryId == libraryId && operation.state == .pending
        }
    }

    func update(_ operation: SyncOperation) async throws {
        guard let index = operations.firstIndex(where: { $0.id == operation.id }) else {
            operations.append(operation)
            return
        }

        operations[index] = operation
    }

    func removeOperation(id: UUID) async throws {
        operations.removeAll { $0.id == id }
    }
}

private actor InMemorySyncIssueStore: SyncIssueStore {
    private(set) var issues: [SyncIssue] = []

    func openIssues(for libraryId: Int64) async throws -> [SyncIssue] {
        issues.filter { issue in
            issue.libraryId == libraryId && issue.resolutionState == .open
        }
    }

    func issue(id: UUID) async throws -> SyncIssue? {
        issues.first { issue in
            issue.id == id
        }
    }

    func save(_ issue: SyncIssue) async throws {
        issues.append(issue)
    }

    func markIssue(id: UUID, as state: SyncIssueResolutionState) async throws {
        guard let index = issues.firstIndex(where: { $0.id == id }) else {
            return
        }

        issues[index].resolutionState = state
    }
}

private actor SequentialEagleAPITransport: EagleAPITransport {
    private var responses: [Data]
    private(set) var requests: [URLRequest] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let data = responses.isEmpty ? Data(#"{"status":"success"}"#.utf8) : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (data, response)
    }
}
