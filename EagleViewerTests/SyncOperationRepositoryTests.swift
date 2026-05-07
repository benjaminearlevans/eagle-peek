//
//  SyncOperationRepositoryTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import Foundation
import XCTest
@testable import EagleViewer

final class SyncOperationRepositoryTests: XCTestCase {
    func test_enqueue_withPendingOperation_shouldReturnOperationInCreatedOrder() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        let first = operation(libraryId: library.id, createdAt: Date(timeIntervalSince1970: 10))
        let second = operation(libraryId: library.id, createdAt: Date(timeIntervalSince1970: 20))

        // Act
        try await repositories.syncOperation.enqueue(second)
        try await repositories.syncOperation.enqueue(first)
        let operations = try await repositories.syncOperation.pendingOperations(for: library.id)

        // Assert
        XCTAssertEqual(operations.map(\.id), [first.id, second.id])
    }

    func test_update_withFailedState_shouldRemoveOperationFromPendingResults() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        var queuedOperation = operation(libraryId: library.id)
        try await repositories.syncOperation.enqueue(queuedOperation)

        // Act
        queuedOperation.state = .failed
        queuedOperation.failureMessage = "Network offline"
        try await repositories.syncOperation.update(queuedOperation)
        let pendingOperations = try await repositories.syncOperation.pendingOperations(for: library.id)
        let failedOperations = try await repositories.syncOperation.operations(for: library.id, states: [.failed])

        // Assert
        XCTAssertTrue(pendingOperations.isEmpty)
        XCTAssertEqual(failedOperations.first?.failureMessage, "Network offline")
    }

    func test_removeOperation_withQueuedOperation_shouldDeleteOperation() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        let queuedOperation = operation(libraryId: library.id)
        try await repositories.syncOperation.enqueue(queuedOperation)

        // Act
        try await repositories.syncOperation.removeOperation(id: queuedOperation.id)
        let operations = try await repositories.syncOperation.pendingOperations(for: library.id)

        // Assert
        XCTAssertTrue(operations.isEmpty)
    }

    func test_operationCount_withMatchingStates_shouldReturnOnlyMatchingOperationCount() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        var failedOperation = operation(libraryId: library.id)
        failedOperation.state = .failed
        let pendingOperation = operation(libraryId: library.id)
        try await repositories.syncOperation.enqueue(failedOperation)
        try await repositories.syncOperation.enqueue(pendingOperation)

        // Act
        let count = try await repositories.syncOperation.operationCount(for: library.id, states: [.pending])

        // Assert
        XCTAssertEqual(count, 1)
    }

    func test_resetOperations_withFailedAndConflictedStates_shouldMakeOperationsPending() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        var failedOperation = operation(libraryId: library.id)
        failedOperation.state = .failed
        failedOperation.failureMessage = "Network offline"
        var conflictedOperation = operation(libraryId: library.id)
        conflictedOperation.state = .conflicted
        conflictedOperation.failureMessage = "Changed on desktop"
        try await repositories.syncOperation.enqueue(failedOperation)
        try await repositories.syncOperation.enqueue(conflictedOperation)

        // Act
        let resetCount = try await repositories.syncOperation.resetOperations(
            for: library.id,
            states: [.failed, .conflicted]
        )
        let pendingOperations = try await repositories.syncOperation.pendingOperations(for: library.id)

        // Assert
        XCTAssertEqual(resetCount, 2)
        XCTAssertEqual(pendingOperations.count, 2)
        XCTAssertTrue(pendingOperations.allSatisfy { $0.failureMessage == nil })
    }

    private func operation(
        libraryId: Int64,
        createdAt: Date = Date()
    ) -> SyncOperation {
        SyncOperation(
            libraryId: libraryId,
            itemId: "ITEM-A",
            kind: .updateItem,
            payload: Data(#"{"id":"ITEM-A","star":5}"#.utf8),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func createLibrary(in repositories: Repositories) async throws -> Library {
        try await repositories.library.create(
            name: "Test Library",
            bookmarkData: Data(),
            useLocalStorage: false
        )
    }
}
