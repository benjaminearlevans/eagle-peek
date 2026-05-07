//
//  SyncIssueTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import XCTest
@testable import EagleViewer

final class SyncIssueTests: XCTestCase {
    func test_syncIssueInitialization_withDefaults_shouldCreateOpenIssue() {
        // Arrange
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)

        // Act
        let issue = SyncIssue(
            id: id,
            libraryId: 7,
            category: .connection,
            severity: .error,
            title: "Offline",
            message: "Eagle Desktop is unreachable.",
            createdAt: createdAt,
            updatedAt: createdAt
        )

        // Assert
        XCTAssertEqual(issue.id, id)
        XCTAssertEqual(issue.libraryId, 7)
        XCTAssertEqual(issue.category, .connection)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.resolutionState, .open)
        XCTAssertEqual(issue.createdAt, createdAt)
    }

    func test_syncOperationInitialization_withDefaults_shouldCreatePendingOperation() {
        // Arrange
        let payload = Data("{}".utf8)

        // Act
        let operation = SyncOperation(
            libraryId: 9,
            itemId: "item-a",
            kind: .updateItem,
            payload: payload,
            baselineModificationTime: 123
        )

        // Assert
        XCTAssertEqual(operation.libraryId, 9)
        XCTAssertEqual(operation.itemId, "item-a")
        XCTAssertEqual(operation.kind, .updateItem)
        XCTAssertEqual(operation.state, .pending)
        XCTAssertEqual(operation.payload, payload)
        XCTAssertEqual(operation.baselineModificationTime, 123)
    }
}
