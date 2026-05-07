//
//  GalleryRenderWindowTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import XCTest
@testable import EagleViewer

final class GalleryRenderWindowTests: XCTestCase {
    func test_initialCount_withSmallTotal_shouldReturnTotal() {
        // Arrange
        let window = GalleryRenderWindow(initialLimit: 100, increment: 50)

        // Act
        let count = window.initialCount(total: 20)

        // Assert
        XCTAssertEqual(count, 20)
    }

    func test_initialCount_withLargeTotal_shouldReturnInitialLimit() {
        // Arrange
        let window = GalleryRenderWindow(initialLimit: 100, increment: 50)

        // Act
        let count = window.initialCount(total: 250)

        // Assert
        XCTAssertEqual(count, 100)
    }

    func test_nextCount_withRemainingItems_shouldAdvanceByIncrement() {
        // Arrange
        let window = GalleryRenderWindow(initialLimit: 100, increment: 50)

        // Act
        let count = window.nextCount(current: 100, total: 250)

        // Assert
        XCTAssertEqual(count, 150)
    }

    func test_nextCount_nearEnd_shouldClampToTotal() {
        // Arrange
        let window = GalleryRenderWindow(initialLimit: 100, increment: 50)

        // Act
        let count = window.nextCount(current: 230, total: 250)

        // Assert
        XCTAssertEqual(count, 250)
    }

    func test_countIncluding_withOffscreenIndex_shouldExpandToIncludeItem() {
        // Arrange
        let window = GalleryRenderWindow(initialLimit: 100, increment: 50)

        // Act
        let count = window.countIncluding(index: 175, current: 100, total: 250)

        // Assert
        XCTAssertEqual(count, 176)
    }
}
