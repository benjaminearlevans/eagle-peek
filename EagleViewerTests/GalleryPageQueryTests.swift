//
//  GalleryPageQueryTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import Foundation
import GRDB
import XCTest
@testable import EagleViewer

final class GalleryPageQueryTests: XCTestCase {
    func test_allGalleryPageRequest_withLimit_shouldReturnLimitedItemsAndTotalCount() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        try await insertItems(count: 3, libraryId: library.id, dbWriter: repositories.dbWriter)
        let request = AllGalleryPageRequest(
            libraryId: library.id,
            sortOption: .defaultValue,
            searchText: "",
            limit: 2
        )

        // Act
        let page = try await repositories.dbWriter.read { db in
            try request.fetch(db)
        }

        // Assert
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.totalCount, 3)
        XCTAssertTrue(page.hasNextPage)
    }

    func test_allGalleryPageRequest_withSearchText_shouldCountMatchingItemsOnly() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        try await insertItems(count: 3, libraryId: library.id, dbWriter: repositories.dbWriter)
        let request = AllGalleryPageRequest(
            libraryId: library.id,
            sortOption: .defaultValue,
            searchText: "Item 2",
            limit: 10
        )

        // Act
        let page = try await repositories.dbWriter.read { db in
            try request.fetch(db)
        }

        // Assert
        XCTAssertEqual(page.items.map(\.name), ["Item 2"])
        XCTAssertEqual(page.totalCount, 1)
    }

    private func createLibrary(in repositories: Repositories) async throws -> Library {
        try await repositories.library.create(
            name: "Test Library",
            bookmarkData: Data(),
            useLocalStorage: false
        )
    }

    private func insertItems(count: Int, libraryId: Int64, dbWriter: any DatabaseWriter) async throws {
        try await dbWriter.write { db in
            for index in 1 ... count {
                var item = StoredItem(
                    libraryId: libraryId,
                    itemId: "ITEM-\(index)",
                    name: "Item \(index)",
                    nameForSort: "Item \(index)",
                    size: 100,
                    btime: Int64(index),
                    mtime: Int64(index),
                    ext: "png",
                    isDeleted: false,
                    modificationTime: Int64(index),
                    height: 100,
                    width: 100,
                    lastModified: Int64(index),
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
}
