//
//  EagleAPILibrarySourceTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import Foundation
import GRDB
import XCTest
@testable import EagleViewer

final class EagleAPILibrarySourceTests: XCTestCase {
    func test_synchronize_withFolderAndItemPages_shouldImportMetadataIntoDatabase() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await repositories.library.createEagleAPI(
            name: "Remote Eagle",
            baseURL: URL(string: "http://localhost:41595/api/v2/")!,
            token: nil,
            libraryPath: "/Users/test/Eagle.library"
        )
        let transport = SequentialEagleAPITransport(responses: [
            folderPageResponse(),
            itemPageResponse(),
        ])
        let client = EagleAPIClient(configuration: .localhost(), transport: transport)
        let source = EagleAPILibrarySource(library: library, apiClient: client)

        // Act
        let result = try await source.synchronize(
            library: library,
            dbWriter: repositories.dbWriter,
            progressHandler: { _ in }
        )
        let importedFolder = try await fetchFolder(libraryId: library.id, folderId: "FOLDER-A", dbWriter: repositories.dbWriter)
        let importedChild = try await fetchFolder(libraryId: library.id, folderId: "FOLDER-B", dbWriter: repositories.dbWriter)
        let importedItem = try await fetchItem(libraryId: library.id, itemId: "ITEM-A", dbWriter: repositories.dbWriter)
        let importedAssignment = try await fetchFolderItem(
            libraryId: library.id,
            folderId: "FOLDER-B",
            itemId: "ITEM-A",
            dbWriter: repositories.dbWriter
        )

        // Assert
        XCTAssertEqual(result.updatedItemCount, 1)
        XCTAssertEqual(result.deletedItemCount, 0)
        XCTAssertEqual(importedFolder?.name, "Design")
        XCTAssertEqual(importedChild?.parentId, "FOLDER-A")
        XCTAssertEqual(importedItem?.name, "Poster")
        XCTAssertEqual(importedItem?.tags, ["print", "reference"])
        XCTAssertEqual(importedAssignment?.orderValue, "42")
    }

    func test_synchronize_withStaleLocalItem_shouldDeleteMissingItems() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await repositories.library.createEagleAPI(
            name: "Remote Eagle",
            baseURL: URL(string: "http://localhost:41595/api/v2/")!,
            token: nil,
            libraryPath: nil
        )
        try await insertStaleItem(libraryId: library.id, dbWriter: repositories.dbWriter)
        let transport = SequentialEagleAPITransport(responses: [
            emptyFolderPageResponse(),
            emptyItemPageResponse(),
        ])
        let client = EagleAPIClient(configuration: .localhost(), transport: transport)
        let source = EagleAPILibrarySource(library: library, apiClient: client)

        // Act
        let result = try await source.synchronize(
            library: library,
            dbWriter: repositories.dbWriter,
            progressHandler: { _ in }
        )
        let staleItem = try await fetchItem(libraryId: library.id, itemId: "STALE", dbWriter: repositories.dbWriter)

        // Assert
        XCTAssertEqual(result.deletedItemCount, 1)
        XCTAssertNil(staleItem)
    }

    private func folderPageResponse() -> Data {
        Data("""
        {
          "status": "success",
          "data": {
            "data": [
              {
                "id": "FOLDER-A",
                "name": "Design",
                "modificationTime": 100,
                "children": [
                  {
                    "id": "FOLDER-B",
                    "name": "Posters",
                    "modificationTime": 110,
                    "children": []
                  }
                ]
              }
            ],
            "total": 1,
            "offset": 0,
            "limit": 1000
          }
        }
        """.utf8)
    }

    private func itemPageResponse() -> Data {
        Data("""
        {
          "status": "success",
          "data": {
            "data": [
              {
                "id": "ITEM-A",
                "name": "Poster",
                "ext": "png",
                "size": 2048,
                "btime": 1,
                "mtime": 2,
                "isDeleted": false,
                "modificationTime": 200,
                "height": 1200,
                "width": 800,
                "lastModified": 3,
                "noThumbnail": false,
                "star": 4,
                "duration": 0,
                "folders": ["FOLDER-B"],
                "order": {
                  "FOLDER-B": "42"
                },
                "tags": ["print", "reference"],
                "annotation": "Collected for layout work."
              }
            ],
            "total": 1,
            "offset": 0,
            "limit": 200
          }
        }
        """.utf8)
    }

    private func emptyFolderPageResponse() -> Data {
        Data("""
        {
          "status": "success",
          "data": {
            "data": [],
            "total": 0,
            "offset": 0,
            "limit": 1000
          }
        }
        """.utf8)
    }

    private func emptyItemPageResponse() -> Data {
        Data("""
        {
          "status": "success",
          "data": {
            "data": [],
            "total": 0,
            "offset": 0,
            "limit": 200
          }
        }
        """.utf8)
    }

    private func fetchFolder(libraryId: Int64, folderId: String, dbWriter: any DatabaseWriter) async throws -> Folder? {
        try await dbWriter.read { db in
            try Folder
                .filter(Column("libraryId") == libraryId)
                .filter(Column("folderId") == folderId)
                .fetchOne(db)
        }
    }

    private func fetchItem(libraryId: Int64, itemId: String, dbWriter: any DatabaseWriter) async throws -> StoredItem? {
        try await dbWriter.read { db in
            try StoredItem
                .filter(Column("libraryId") == libraryId)
                .filter(Column("itemId") == itemId)
                .fetchOne(db)
        }
    }

    private func fetchFolderItem(
        libraryId: Int64,
        folderId: String,
        itemId: String,
        dbWriter: any DatabaseWriter
    ) async throws -> FolderItem? {
        try await dbWriter.read { db in
            try FolderItem
                .filter(Column("libraryId") == libraryId)
                .filter(Column("folderId") == folderId)
                .filter(Column("itemId") == itemId)
                .fetchOne(db)
        }
    }

    private func insertStaleItem(libraryId: Int64, dbWriter: any DatabaseWriter) async throws {
        try await dbWriter.write { db in
            var item = StoredItem(
                libraryId: libraryId,
                itemId: "STALE",
                name: "Stale",
                nameForSort: "Stale",
                size: 100,
                btime: 0,
                mtime: 0,
                ext: "png",
                isDeleted: false,
                modificationTime: 1,
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
}

private actor SequentialEagleAPITransport: EagleAPITransport {
    private var responses: [Data]

    init(responses: [Data]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let data = responses.isEmpty ? Data(#"{"status":"success","data":{"data":[],"total":0,"offset":0,"limit":50}}"#.utf8) : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (data, response)
    }
}
