//
//  GalleryDescriptorTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import XCTest
@testable import EagleViewer

final class GalleryDescriptorTests: XCTestCase {
    func test_galleryFilterState_withDefaultValues_shouldBeEmpty() {
        // Arrange & Act
        let filterState = GalleryFilterState.empty

        // Assert
        XCTAssertTrue(filterState.isEmpty)
        XCTAssertEqual(filterState.mediaKind, .all)
        XCTAssertEqual(filterState.searchText, "")
    }

    func test_galleryFilterState_withSearchText_shouldNotBeEmpty() {
        // Arrange
        let filterState = GalleryFilterState(mediaKind: .all, searchText: "poster")

        // Act
        let isEmpty = filterState.isEmpty

        // Assert
        XCTAssertFalse(isEmpty)
    }

    func test_galleryScope_withFolder_shouldReturnFolderLibraryId() {
        // Arrange
        let folderId = Folder.ID(libraryId: 42, folderId: "folder-a")
        let scope = GalleryScope.folder(folderId)

        // Act
        let libraryId = scope.libraryId

        // Assert
        XCTAssertEqual(libraryId, 42)
    }

    func test_galleryPageRequest_withInvalidBounds_shouldClampValues() {
        // Arrange
        let descriptor = GalleryDescriptor(scope: .all(libraryId: 1))

        // Act
        let request = GalleryPageRequest(descriptor: descriptor, offset: -10, limit: 0)

        // Assert
        XCTAssertEqual(request.offset, 0)
        XCTAssertEqual(request.limit, 1)
    }

    func test_galleryPage_withRemainingItems_shouldHaveNextPage() {
        // Arrange
        let item = Item(
            libraryId: 1,
            itemId: "item-a",
            name: "A",
            ext: "png",
            height: 100,
            width: 100,
            noThumbnail: false,
            duration: 0
        )
        let page = GalleryPage(items: [item], totalCount: 2, offset: 0, limit: 1)

        // Act
        let hasNextPage = page.hasNextPage

        // Assert
        XCTAssertTrue(hasNextPage)
    }
}
