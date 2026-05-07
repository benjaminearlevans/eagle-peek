//
//  MediaFileResolverTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import Foundation
import XCTest
@testable import EagleViewer

final class MediaFileResolverTests: XCTestCase {
    func test_resolve_withMissingLibraryURL_shouldReturnMissingLibraryURL() {
        // Arrange
        let resolver = MediaFileResolver(libraryURL: nil)
        let item = TestPathItem()

        // Act
        let resolution = resolver.resolve(.original, for: item)

        // Assert
        XCTAssertEqual(resolution, .missingLibraryURL)
    }

    func test_resolve_withExistingOriginalFile_shouldReturnAvailableURL() {
        // Arrange
        let libraryURL = URL(fileURLWithPath: "/Library.eagle", isDirectory: true)
        let resolver = MediaFileResolver(libraryURL: libraryURL) { url in
            url.path.hasSuffix("/images/ITEM-A.info/Poster.png")
        }
        let item = TestPathItem()

        // Act
        let resolution = resolver.resolve(.original, for: item)

        // Assert
        XCTAssertEqual(
            resolution,
            .available(URL(fileURLWithPath: "/Library.eagle/images/ITEM-A.info/Poster.png"))
        )
    }

    func test_resolve_withMissingThumbnailFile_shouldReturnMissingFileURL() {
        // Arrange
        let libraryURL = URL(fileURLWithPath: "/Library.eagle", isDirectory: true)
        let resolver = MediaFileResolver(libraryURL: libraryURL) { _ in false }
        let item = TestPathItem()

        // Act
        let resolution = resolver.resolve(.thumbnail, for: item)

        // Assert
        XCTAssertEqual(
            resolution,
            .missingFile(URL(fileURLWithPath: "/Library.eagle/images/ITEM-A.info/Poster_thumbnail.png"))
        )
    }
}

private struct TestPathItem: ItemPathProvider {
    let itemId = "ITEM-A"
    let name = "Poster"
    let ext = "png"
    let noThumbnail = false
}
