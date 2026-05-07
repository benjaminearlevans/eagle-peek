//
//  GalleryRenderWindow.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

struct GalleryRenderWindow: Equatable {
    static let defaultInitialLimit = 240
    static let defaultIncrement = 160

    let initialLimit: Int
    let increment: Int

    init(
        initialLimit: Int = Self.defaultInitialLimit,
        increment: Int = Self.defaultIncrement
    ) {
        self.initialLimit = max(1, initialLimit)
        self.increment = max(1, increment)
    }

    func initialCount(total: Int) -> Int {
        min(max(0, total), initialLimit)
    }

    func nextCount(current: Int, total: Int) -> Int {
        let safeCurrent = max(current, initialCount(total: total))
        return min(max(0, total), safeCurrent + increment)
    }

    func countIncluding(index: Int, current: Int, total: Int) -> Int {
        guard index >= current else {
            return current
        }

        return min(max(0, total), index + 1)
    }
}
