//
//  SyncIssueRepositoryTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import XCTest
@testable import EagleViewer

final class SyncIssueRepositoryTests: XCTestCase {
    func test_openIssues_withSavedOpenIssue_shouldReturnIssue() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        let issue = SyncIssue(
            libraryId: library.id,
            category: .importMetadata,
            severity: .warning,
            title: "Read metadata failed",
            message: "metadata.json is missing"
        )

        // Act
        try await repositories.syncIssue.save(issue)
        let issues = try await repositories.syncIssue.openIssues(for: library.id)

        // Assert
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.id, issue.id)
        XCTAssertEqual(issues.first?.resolutionState, .open)
    }

    func test_markIssue_withResolvedState_shouldRemoveIssueFromOpenIssues() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        let issue = SyncIssue(
            libraryId: library.id,
            category: .importMetadata,
            severity: .warning,
            title: "Read metadata failed",
            message: "metadata.json is missing"
        )
        try await repositories.syncIssue.save(issue)

        // Act
        try await repositories.syncIssue.markIssue(id: issue.id, as: .resolved)
        let issues = try await repositories.syncIssue.openIssues(for: library.id)

        // Assert
        XCTAssertTrue(issues.isEmpty)
    }

    func test_replaceOpenImportIssues_withNewIssue_shouldResolvePreviousImportIssues() async throws {
        // Arrange
        let repositories = Repositories.empty()
        let library = try await createLibrary(in: repositories)
        let oldIssue = SyncIssue(
            libraryId: library.id,
            category: .importMetadata,
            severity: .warning,
            title: "Old issue",
            message: "Old failure"
        )
        let newIssue = SyncIssue(
            libraryId: library.id,
            category: .copyMedia,
            severity: .warning,
            title: "New issue",
            message: "New failure"
        )
        try await repositories.syncIssue.save(oldIssue)

        // Act
        try await repositories.syncIssue.replaceOpenImportIssues(for: library.id, with: [newIssue])
        let issues = try await repositories.syncIssue.openIssues(for: library.id)

        // Assert
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.id, newIssue.id)
    }

    private func createLibrary(in repositories: Repositories) async throws -> Library {
        try await repositories.library.create(
            name: "Test Library",
            bookmarkData: Data(),
            useLocalStorage: false
        )
    }
}
