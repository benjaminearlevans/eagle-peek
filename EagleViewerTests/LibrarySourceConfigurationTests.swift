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
}
