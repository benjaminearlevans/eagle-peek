//
//  ImportIssueMapperTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import XCTest
@testable import EagleViewer

final class ImportIssueMapperTests: XCTestCase {
    func test_issues_withSuccessfulImport_shouldReturnNoIssues() {
        // Arrange
        let summary = MetadataImporter.ImportRunSummary()

        // Act
        let issues = ImportIssueMapper.issues(
            libraryId: 1,
            status: .success,
            summary: summary,
            fatalErrorMessage: nil
        )

        // Assert
        XCTAssertTrue(issues.isEmpty)
    }

    func test_issues_withMetadataFailure_shouldCreateItemIssue() {
        // Arrange
        var summary = MetadataImporter.ImportRunSummary()
        summary.failedItems = [
            MetadataImporter.ImportItemFailure(
                itemId: "abc123",
                operation: "Read metadata",
                message: "metadata.json is missing"
            ),
        ]

        // Act
        let issues = ImportIssueMapper.issues(
            libraryId: 42,
            status: .partial,
            summary: summary,
            fatalErrorMessage: nil
        )

        // Assert
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.libraryId, 42)
        XCTAssertEqual(issues.first?.itemId, "abc123")
        XCTAssertEqual(issues.first?.category, .importMetadata)
        XCTAssertEqual(issues.first?.severity, .warning)
    }

    func test_issues_withFatalError_shouldCreateConnectionIssue() {
        // Arrange
        let summary = MetadataImporter.ImportRunSummary()

        // Act
        let issues = ImportIssueMapper.issues(
            libraryId: 7,
            status: .failed,
            summary: summary,
            fatalErrorMessage: "Folder access denied"
        )

        // Assert
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.libraryId, 7)
        XCTAssertNil(issues.first?.itemId)
        XCTAssertEqual(issues.first?.category, .connection)
        XCTAssertEqual(issues.first?.severity, .error)
    }
}
