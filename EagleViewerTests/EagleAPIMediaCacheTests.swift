//
//  EagleAPIMediaCacheTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import Foundation
import XCTest
@testable import EagleViewer

final class EagleAPIMediaCacheTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        let fileManager = FileManager.default
        for directory in temporaryDirectories {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func test_cachePreviews_withReachableThumbnail_shouldCopyThumbnailToLocalCache() async throws {
        // Arrange
        let sourceLibraryURL = try makeTemporaryDirectory()
        let destinationLibraryURL = try makeTemporaryDirectory()
        let item = makeStoredItem()
        let sourceThumbnailURL = sourceLibraryURL.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
        let expectedData = Data([0x45, 0x50, 0x4b])
        try FileManager.default.createDirectory(
            at: sourceThumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try expectedData.write(to: sourceThumbnailURL)
        let cache = EagleAPIMediaCache(
            sourceLibraryURL: sourceLibraryURL,
            destinationLibraryURL: destinationLibraryURL
        )

        // Act
        let result = await cache.cachePreviews(for: [item])
        let cachedThumbnailURL = destinationLibraryURL.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
        let cachedData = try Data(contentsOf: cachedThumbnailURL)

        // Assert
        XCTAssertNil(cache.unavailableResult())
        XCTAssertEqual(result.failureCount, 0)
        XCTAssertEqual(cachedData, expectedData)
    }

    func test_unavailableResult_withUnreachableSource_shouldReportMediaIssue() throws {
        // Arrange
        let sourceLibraryURL = try makeTemporaryDirectory()
        let destinationLibraryURL = try makeTemporaryDirectory()
        let cache = EagleAPIMediaCache(
            sourceLibraryURL: sourceLibraryURL,
            destinationLibraryURL: destinationLibraryURL
        )

        // Act
        let result = cache.unavailableResult()

        // Assert
        XCTAssertEqual(result?.failureCount, 1)
        XCTAssertTrue(result?.latestIssueMessage?.contains("cannot read") == true)
    }

    func test_unavailableResult_withBookmarkAccessFailure_shouldUseRecoveryMessage() throws {
        // Arrange
        let destinationLibraryURL = try makeTemporaryDirectory()
        let recoveryMessage = "Re-select the Eagle library folder in Settings."
        let cache = EagleAPIMediaCache(
            sourceLibraryURL: nil,
            destinationLibraryURL: destinationLibraryURL,
            sourceUnavailableMessage: recoveryMessage
        )

        // Act
        let result = cache.unavailableResult()

        // Assert
        XCTAssertEqual(result?.failureCount, 1)
        XCTAssertEqual(result?.latestIssueMessage, recoveryMessage)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EagleAPIMediaCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeStoredItem() -> StoredItem {
        StoredItem(
            libraryId: 1,
            itemId: "ITEM-A",
            name: "Poster",
            nameForSort: "Poster",
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
    }
}
