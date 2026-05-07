//
//  GalleryDescriptor.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

enum GalleryMediaKind: String, CaseIterable, Codable, Hashable {
    case all
    case photo
    case animated
    case video
    case text
}

enum GalleryScope: Codable, Hashable {
    case all(libraryId: Int64)
    case uncategorized(libraryId: Int64)
    case random(libraryId: Int64)
    case folder(Folder.ID)
    case smartFolder(libraryId: Int64, smartFolderId: String)
    case search(libraryId: Int64, text: String)

    var libraryId: Int64 {
        switch self {
        case .all(let libraryId),
             .uncategorized(let libraryId),
             .random(let libraryId),
             .smartFolder(let libraryId, _),
             .search(let libraryId, _):
            return libraryId
        case .folder(let folderId):
            return folderId.libraryId
        }
    }
}

struct GalleryFilterState: Codable, Equatable, Hashable {
    var mediaKind: GalleryMediaKind
    var searchText: String

    static let empty = GalleryFilterState(mediaKind: .all, searchText: "")

    var isEmpty: Bool {
        mediaKind == .all && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct GalleryDescriptor: Codable, Equatable, Hashable {
    var scope: GalleryScope
    var sortOption: GlobalSortOption
    var filterState: GalleryFilterState

    init(
        scope: GalleryScope,
        sortOption: GlobalSortOption = .defaultValue,
        filterState: GalleryFilterState = .empty
    ) {
        self.scope = scope
        self.sortOption = sortOption
        self.filterState = filterState
    }
}

struct GalleryPageRequest: Equatable {
    let descriptor: GalleryDescriptor
    let offset: Int
    let limit: Int

    init(descriptor: GalleryDescriptor, offset: Int, limit: Int) {
        self.descriptor = descriptor
        self.offset = max(0, offset)
        self.limit = max(1, limit)
    }
}

struct GalleryPage: Equatable {
    let items: [Item]
    let totalCount: Int
    let offset: Int
    let limit: Int

    var hasNextPage: Bool {
        offset + items.count < totalCount
    }
}
