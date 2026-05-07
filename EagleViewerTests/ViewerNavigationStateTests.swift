//
//  ViewerNavigationStateTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import XCTest
@testable import EagleViewer

final class ViewerNavigationStateTests: XCTestCase {
    func test_canGoPrevious_withFirstItem_shouldReturnFalse() {
        // Arrange
        let state = ViewerNavigationState(currentIndex: 0, totalCount: 3)

        // Act & Assert
        XCTAssertFalse(state.canGoPrevious)
    }

    func test_canGoNext_withMiddleItem_shouldReturnTrue() {
        // Arrange
        let state = ViewerNavigationState(currentIndex: 1, totalCount: 3)

        // Act & Assert
        XCTAssertTrue(state.canGoNext)
    }

    func test_index_withValidOffset_shouldReturnTargetIndex() {
        // Arrange
        let state = ViewerNavigationState(currentIndex: 1, totalCount: 3)

        // Act
        let index = state.index(offsetBy: 1)

        // Assert
        XCTAssertEqual(index, 2)
    }

    func test_index_withOutOfBoundsOffset_shouldReturnNil() {
        // Arrange
        let state = ViewerNavigationState(currentIndex: 2, totalCount: 3)

        // Act
        let index = state.index(offsetBy: 1)

        // Assert
        XCTAssertNil(index)
    }
}
