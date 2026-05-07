//
//  LibrarySourceConfigurationTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import Foundation
import XCTest
@testable import EagleViewer

final class LibrarySourceConfigurationTests: XCTestCase {
    func test_createEagleAPI_withConnectionDetails_shouldPersistSourceConfiguration() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let baseURL = URL(string: "http://192.168.1.50:41595/api/v2/")!

        // Act
        let library = try await repositories.library.createEagleAPI(
            name: "Remote Eagle",
            baseURL: baseURL,
            token: "api-token",
            libraryPath: "/Users/test/Eagle.library"
        )

        // Assert
        XCTAssertTrue(library.isEagleAPISource)
        XCTAssertEqual(library.sourceKind, .eagleAPI)
        XCTAssertEqual(library.apiBaseURL, baseURL.absoluteString)
        XCTAssertEqual(library.apiToken, "api-token")
        XCTAssertEqual(library.apiLibraryPath, "/Users/test/Eagle.library")
        XCTAssertEqual(library.eagleAPIConfiguration?.normalizedBaseURL, baseURL)
        XCTAssertEqual(library.eagleAPILibraryURL?.path, "/Users/test/Eagle.library")
    }

    func test_updateEagleAPIMediaFolder_withAPILibrary_shouldStorePreviewBookmarkWithoutChangingSourceMode() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await repositories.library.createEagleAPI(
            name: "Remote Eagle",
            baseURL: URL(string: "http://192.168.1.50:41595/api/v2/")!,
            token: "api-token",
            libraryPath: "/Users/test/Eagle.library"
        )
        let bookmarkData = Data("preview-folder-bookmark".utf8)

        // Act
        let updatedLibrary = try await repositories.library.updateEagleAPIMediaFolder(
            id: library.id,
            bookmarkData: bookmarkData
        )

        // Assert
        XCTAssertTrue(updatedLibrary.isEagleAPISource)
        XCTAssertTrue(updatedLibrary.hasEagleAPIMediaFolder)
        XCTAssertEqual(updatedLibrary.bookmarkData, bookmarkData)
        XCTAssertFalse(updatedLibrary.useLocalStorage)
        XCTAssertEqual(updatedLibrary.apiBaseURL, library.apiBaseURL)
        XCTAssertEqual(updatedLibrary.apiToken, library.apiToken)
        XCTAssertEqual(updatedLibrary.apiLibraryPath, library.apiLibraryPath)
        XCTAssertEqual(updatedLibrary.lastImportedFolderMTime, 0)
        XCTAssertEqual(updatedLibrary.lastImportedItemMTime, 0)
        XCTAssertEqual(updatedLibrary.lastImportStatus, .none)
        XCTAssertNil(updatedLibrary.lastImportError)
        XCTAssertEqual(updatedLibrary.lastImportFailureCount, 0)
    }
}
