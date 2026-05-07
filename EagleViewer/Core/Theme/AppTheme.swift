//
//  AppTheme.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import SwiftUI

enum AppTheme {
    enum Layout {
        static let minimumTouchTarget: CGFloat = 44
        static let compactControlHeight: CGFloat = 44
        static let horizontalPagePadding: CGFloat = 20
    }

    enum Radius {
        static let small: CGFloat = 6
        static let card: CGFloat = 8
        static let panel: CGFloat = 12
        static let control: CGFloat = 22
    }

    enum Colors {
        static let appBackground = Color(uiColor: .systemBackground)
        static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
        static let groupedBackground = Color(uiColor: .systemGroupedBackground)
        static let placeholderFill = Color(uiColor: .tertiarySystemFill)
        static let placeholderSymbol = Color(uiColor: .tertiaryLabel)
        static let subtleFill = Color(uiColor: .secondarySystemFill)
        static let separator = Color(uiColor: .separator)
        static let glassFallbackFill = Color(uiColor: .secondarySystemBackground)
        static let glassPressedFill = Color(uiColor: .tertiarySystemFill)
        static let imageOverlayText = Color.white
        static let imageOverlayShadow = Color.black.opacity(0.45)
    }

    enum Status {
        static let success = Color.green
        static let warning = Color.orange
        static let critical = Color.red
        static let neutral = Color.secondary
    }
}
