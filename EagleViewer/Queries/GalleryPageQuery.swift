//
//  GalleryPageQuery.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import GRDB
import GRDBQuery

enum GalleryPageSize {
    static let initial = 240
    static let increment = 240
}

protocol GalleryPageQueryable: ValueObservationQueryable where Value == GalleryPage, Context == DatabaseContext {
    var limit: Int { get set }
}

struct AllGalleryPageRequest: GalleryPageQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption
    var searchText: String = ""
    var limit: Int = GalleryPageSize.initial

    static var defaultValue: GalleryPage {
        GalleryPage(items: [], totalCount: 0, offset: 0, limit: GalleryPageSize.initial)
    }

    func fetch(_ db: Database) throws -> GalleryPage {
        let totalCount = try ItemQuery.searchItems(libraryId: libraryId, searchText: searchText)
            .fetchCount(db)
        let items = try ItemQuery.allItems(libraryId: libraryId, sortOption: sortOption, searchText: searchText)
            .limit(limit)
            .fetchAll(db)

        return GalleryPage(items: items, totalCount: totalCount, offset: 0, limit: limit)
    }
}

struct UncategorizedGalleryPageRequest: GalleryPageQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption
    var searchText: String = ""
    var limit: Int = GalleryPageSize.initial

    static var defaultValue: GalleryPage {
        GalleryPage(items: [], totalCount: 0, offset: 0, limit: GalleryPageSize.initial)
    }

    func fetch(_ db: Database) throws -> GalleryPage {
        let totalCount = try ItemQuery.uncategorizedStoredItems(libraryId: libraryId, searchText: searchText)
            .fetchCount(db)
        let items = try ItemQuery.uncategorizedItems(libraryId: libraryId, sortOption: sortOption, searchText: searchText)
            .limit(limit)
            .fetchAll(db)

        return GalleryPage(items: items, totalCount: totalCount, offset: 0, limit: limit)
    }
}

struct RandomGalleryPageRequest: GalleryPageQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption
    var searchText: String = ""
    var limit: Int = GalleryPageSize.initial

    static var defaultValue: GalleryPage {
        GalleryPage(items: [], totalCount: 0, offset: 0, limit: GalleryPageSize.initial)
    }

    func fetch(_ db: Database) throws -> GalleryPage {
        let totalCount = try ItemQuery.searchItems(libraryId: libraryId, searchText: searchText)
            .fetchCount(db)
        let items = try ItemQuery.randomItems(libraryId: libraryId, searchText: searchText)
            .limit(limit)
            .fetchAll(db)

        return GalleryPage(items: items, totalCount: totalCount, offset: 0, limit: limit)
    }
}

struct FolderGalleryPageRequest: GalleryPageQueryable {
    var folder: Folder
    var globalSortOption: GlobalSortOption
    var searchText: String = ""
    var limit: Int = GalleryPageSize.initial

    static var defaultValue: GalleryPage {
        GalleryPage(items: [], totalCount: 0, offset: 0, limit: GalleryPageSize.initial)
    }

    func fetch(_ db: Database) throws -> GalleryPage {
        let baseItems = ItemQuery.searchItems(libraryId: folder.libraryId, searchText: searchText)
            .joining(required: StoredItem.folderItems.filter(Column("folderId") == folder.folderId))
        let totalCount = try baseItems.fetchCount(db)
        let items = try FolderQuery.folderItems(folder: folder, globalSortOption: globalSortOption, searchText: searchText)
            .limit(limit)
            .fetchAll(db)

        return GalleryPage(items: items, totalCount: totalCount, offset: 0, limit: limit)
    }
}
