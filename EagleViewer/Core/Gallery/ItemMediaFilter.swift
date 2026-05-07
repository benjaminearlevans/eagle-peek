//
//  ItemMediaFilter.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

enum ItemMediaFilter: String, CaseIterable, Identifiable {
    case all
    case photos
    case animated
    case videos
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return String(localized: "All")
        case .photos:
            return String(localized: "Photos")
        case .animated:
            return String(localized: "GIF")
        case .videos:
            return String(localized: "Videos")
        case .text:
            return String(localized: "Text")
        }
    }

    func items(from items: [Item]) -> [Item] {
        guard self != .all else {
            return items
        }

        return items.filter { item in
            item.mediaFilter == self
        }
    }

    static func availableFilters(for items: [Item]) -> [ItemMediaFilter] {
        var hasPhotos = false
        var hasAnimated = false
        var hasVideos = false
        var hasText = false

        for item in items {
            switch item.mediaFilter {
            case .photos:
                hasPhotos = true
            case .animated:
                hasAnimated = true
            case .videos:
                hasVideos = true
            case .text:
                hasText = true
            case .all:
                break
            }

            if hasPhotos && hasAnimated && hasVideos && hasText {
                break
            }
        }

        var filters: [ItemMediaFilter] = [.all]
        if hasPhotos {
            filters.append(.photos)
        }
        if hasAnimated {
            filters.append(.animated)
        }
        if hasVideos {
            filters.append(.videos)
        }
        if hasText {
            filters.append(.text)
        }
        return filters
    }
}

extension Item {
    var mediaFilter: ItemMediaFilter {
        if isVideo {
            return .videos
        }

        if isTextFile {
            return .text
        }

        if isAnimatedImage {
            return .animated
        }

        return .photos
    }
}
