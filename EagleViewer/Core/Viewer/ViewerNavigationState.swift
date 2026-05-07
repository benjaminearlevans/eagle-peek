//
//  ViewerNavigationState.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

struct ViewerNavigationState: Equatable {
    let currentIndex: Int?
    let totalCount: Int

    var canGoPrevious: Bool {
        guard let currentIndex else {
            return false
        }

        return currentIndex > 0
    }

    var canGoNext: Bool {
        guard let currentIndex else {
            return false
        }

        return currentIndex < totalCount - 1
    }

    func index(offsetBy offset: Int) -> Int? {
        guard let currentIndex else {
            return nil
        }

        let nextIndex = currentIndex + offset
        guard (0 ..< totalCount).contains(nextIndex) else {
            return nil
        }

        return nextIndex
    }
}
