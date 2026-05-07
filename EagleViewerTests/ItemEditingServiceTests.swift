//
//  ItemEditingServiceTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import Foundation
import GRDB
import XCTest
@testable import EagleViewer

final class ItemEditingServiceTests: XCTestCase {
    func test_setRating_withExistingItem_shouldUpdateLocalItemAndQueueSyncOperation() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        let itemId = Item.ID(libraryId: library.id, itemId: "ITEM-A")
        try await insertItem(itemId: itemId, dbWriter: repositories.dbWriter)
        let service = ItemEditingService(dbWriter: repositories.dbWriter)

        // Act
        try await service.setRating(itemId: itemId, rating: 5)
        let storedItem = try await fetchItem(itemId: itemId, dbWriter: repositories.dbWriter)
        let operations = try await repositories.syncOperation.pendingOperations(for: library.id)
        let payload = try SyncOperationEncoder().decodeUpdateItem(from: operations.first!.payload)

        // Assert
        XCTAssertEqual(storedItem?.star, 5)
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(payload.id, "ITEM-A")
        XCTAssertEqual(payload.star, 5)
        XCTAssertEqual(operations.first?.baselineModificationTime, 100)
    }

    func test_replaceTags_withDuplicatesAndWhitespace_shouldNormalizeTagsBeforeQueueing() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        let itemId = Item.ID(libraryId: library.id, itemId: "ITEM-A")
        try await insertItem(itemId: itemId, dbWriter: repositories.dbWriter)
        let service = ItemEditingService(dbWriter: repositories.dbWriter)

        // Act
        try await service.replaceTags(itemId: itemId, tags: [" poster ", "Poster", "", "design"])
        let storedItem = try await fetchItem(itemId: itemId, dbWriter: repositories.dbWriter)
        let operations = try await repositories.syncOperation.pendingOperations(for: library.id)
        let payload = try SyncOperationEncoder().decodeUpdateItem(from: operations.first!.payload)

        // Assert
        XCTAssertEqual(storedItem?.tags, ["poster", "design"])
        XCTAssertEqual(payload.tags, ["poster", "design"])
    }

    func test_setRating_withAPIClientSuccess_shouldWriteThroughAndClearQueuedOperation() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        let itemId = Item.ID(libraryId: library.id, itemId: "ITEM-A")
        try await insertItem(itemId: itemId, dbWriter: repositories.dbWriter)
        let transport = RecordingEagleAPITransport(responses: [
            Data(#"{"status":"success"}"#.utf8),
        ])
        let client = EagleAPIClient(configuration: .localhost(), transport: transport)
        let service = ItemEditingService(dbWriter: repositories.dbWriter, apiClient: client)

        // Act
        try await service.setRating(itemId: itemId, rating: 4)
        let operations = try await repositories.syncOperation.pendingOperations(for: library.id)
        let requests = await transport.requests
        let requestBody = try XCTUnwrap(requests.first?.httpBody)
        let updateRequest = try JSONDecoder().decode(EagleItemUpdateRequest.self, from: requestBody)

        // Assert
        XCTAssertTrue(operations.isEmpty)
        XCTAssertEqual(requests.first?.url?.path, "/api/v2/item/update")
        XCTAssertEqual(updateRequest.id, "ITEM-A")
        XCTAssertEqual(updateRequest.star, 4)
    }

    func test_replaceTags_withAPIClientFailure_shouldKeepQueuedOperationForRetry() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        let itemId = Item.ID(libraryId: library.id, itemId: "ITEM-A")
        try await insertItem(itemId: itemId, dbWriter: repositories.dbWriter)
        let transport = FailingEagleAPITransport(error: URLError(.cannotConnectToHost))
        let client = EagleAPIClient(
            configuration: .localhost(),
            transport: transport,
            retryPolicy: .none
        )
        let service = ItemEditingService(dbWriter: repositories.dbWriter, apiClient: client)

        // Act
        do {
            try await service.replaceTags(itemId: itemId, tags: ["synced"])
            XCTFail("Expected API write-through to throw.")
        } catch {
            // Assert below.
        }
        let storedItem = try await fetchItem(itemId: itemId, dbWriter: repositories.dbWriter)
        let operations = try await repositories.syncOperation.pendingOperations(for: library.id)
        let payload = try SyncOperationEncoder().decodeUpdateItem(from: operations.first!.payload)
        let requestCount = await transport.requestCount

        // Assert
        XCTAssertEqual(storedItem?.tags, ["synced"])
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(payload.tags, ["synced"])
        XCTAssertEqual(requestCount, 1)
    }

    private func createLibrary(in repositories: Repositories) async throws -> Library {
        try await repositories.library.create(
            name: "Test Library",
            bookmarkData: Data(),
            useLocalStorage: false
        )
    }

    private func insertItem(itemId: Item.ID, dbWriter: any DatabaseWriter) async throws {
        try await dbWriter.write { db in
            var item = StoredItem(
                libraryId: itemId.libraryId,
                itemId: itemId.itemId,
                name: "Item",
                nameForSort: "Item",
                size: 100,
                btime: 0,
                mtime: 0,
                ext: "png",
                isDeleted: false,
                modificationTime: 100,
                height: 100,
                width: 100,
                lastModified: 0,
                noThumbnail: false,
                star: 0,
                duration: 0,
                tags: [],
                annotation: ""
            )
            try item.insert(db)
        }
    }

    private func fetchItem(itemId: Item.ID, dbWriter: any DatabaseWriter) async throws -> StoredItem? {
        try await dbWriter.read { db in
            try StoredItem
                .filter(Column("libraryId") == itemId.libraryId)
                .filter(Column("itemId") == itemId.itemId)
                .fetchOne(db)
        }
    }
}

private actor RecordingEagleAPITransport: EagleAPITransport {
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

private actor FailingEagleAPITransport: EagleAPITransport {
    private let error: Error
    private(set) var requestCount = 0

    init(error: Error) {
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        throw error
    }
}
