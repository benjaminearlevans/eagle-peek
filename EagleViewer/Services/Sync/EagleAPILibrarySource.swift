//
//  EagleAPILibrarySource.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation
import GRDB

struct EagleAPILibrarySource: LibrarySource {
    let identity: LibrarySourceIdentity

    private let apiClient: EagleAPIClient

    init(library: Library, apiClient: EagleAPIClient) {
        identity = LibrarySourceIdentity(
            kind: .eagleAPI,
            libraryId: library.id,
            displayName: library.name,
            isWritable: true
        )
        self.apiClient = apiClient
    }

    func synchronize(
        library: Library,
        activeLibraryURL: URL?,
        repositories: Repositories,
        fullSync: Bool,
        progressHandler: @escaping (Double) async -> Void
    ) async throws -> LibrarySyncResult {
        try await synchronize(
            library: library,
            dbWriter: repositories.dbWriter,
            progressHandler: progressHandler
        )
    }

    func synchronize(
        library: Library,
        dbWriter: any DatabaseWriter,
        progressHandler: @escaping (Double) async -> Void
    ) async throws -> LibrarySyncResult {
        try await importFolders(libraryId: library.id, dbWriter: dbWriter)
        await progressHandler(0.1)

        let result = try await importItems(
            libraryId: library.id,
            dbWriter: dbWriter,
            progressHandler: { progress in
                await progressHandler(0.1 + 0.9 * progress)
            }
        )

        await progressHandler(1.0)
        return result
    }

    private func importFolders(libraryId: Int64, dbWriter: any DatabaseWriter) async throws {
        let folders = try await allFolders()
        try await dbWriter.write { db in
            let existingFolderIds = try Set(
                String.fetchAll(db, sql: "SELECT folderId FROM folder WHERE libraryId = ?", arguments: [libraryId])
            )
            var processedFolderIds = Set<String>()
            var manualOrder = 0

            for folder in folders {
                try processFolder(
                    db: db,
                    folder: folder,
                    libraryId: libraryId,
                    parentId: nil,
                    manualOrder: &manualOrder,
                    processedFolderIds: &processedFolderIds,
                    existingFolderIds: existingFolderIds
                )
            }

            let foldersToDelete = existingFolderIds.subtracting(processedFolderIds)
            for folderId in foldersToDelete {
                try db.execute(sql: "DELETE FROM folderItem WHERE libraryId = ? AND folderId = ?", arguments: [libraryId, folderId])
                try db.execute(sql: "DELETE FROM folder WHERE libraryId = ? AND folderId = ?", arguments: [libraryId, folderId])
            }
        }
    }

    private func allFolders() async throws -> [EagleFolder] {
        var folders: [EagleFolder] = []
        var offset = 0
        let limit = 1_000

        while true {
            try Task.checkCancellation()

            let page = try await apiClient.folders(EagleFolderGetRequest(offset: offset, limit: limit))
            folders.append(contentsOf: page.data)

            guard page.hasNextPage, !page.data.isEmpty else {
                return folders
            }

            offset += page.data.count
        }
    }

    private func importItems(
        libraryId: Int64,
        dbWriter: any DatabaseWriter,
        progressHandler: @escaping (Double) async -> Void
    ) async throws -> LibrarySyncResult {
        var offset = 0
        let limit = 200
        var processedItemIds = Set<String>()
        var updatedItemCount = 0

        while true {
            try Task.checkCancellation()

            let page = try await apiClient.items(EagleItemGetRequest(
                offset: offset,
                limit: limit,
                fields: [
                    "id", "name", "ext", "size", "btime", "mtime", "isDeleted", "modificationTime",
                    "height", "width", "lastModified", "noThumbnail", "star", "duration",
                    "folders", "order", "tags", "annotation",
                ]
            ))

            let storedItems = page.data.map { item in
                buildItem(libraryId: libraryId, item: item)
            }

            try await dbWriter.write { db in
                for (index, storedItem) in storedItems.enumerated() {
                    let item = page.data[index]
                    var mutableItem = storedItem
                    try mutableItem.save(db)
                    try replaceFolderAssignments(db: db, item: item, storedItem: storedItem)
                }
            }
            processedItemIds.formUnion(storedItems.map(\.itemId))
            updatedItemCount += storedItems.count

            if page.total > 0 {
                await progressHandler(min(0.95, Double(offset + page.data.count) / Double(page.total)))
            }

            guard page.hasNextPage, !page.data.isEmpty else {
                break
            }

            offset += page.data.count
        }

        let deletedItemCount = try await deleteStaleItems(
            libraryId: libraryId,
            processedItemIds: processedItemIds,
            dbWriter: dbWriter
        )

        return LibrarySyncResult(
            updatedItemCount: updatedItemCount,
            deletedItemCount: deletedItemCount,
            failureCount: 0,
            latestIssueMessage: nil
        )
    }

    private func deleteStaleItems(
        libraryId: Int64,
        processedItemIds: Set<String>,
        dbWriter: any DatabaseWriter
    ) async throws -> Int {
        try await dbWriter.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS temp_api_current_items")
            try db.execute(sql: "CREATE TEMPORARY TABLE temp_api_current_items (itemId TEXT)")
            let insertStatement = try db.makeStatement(sql: "INSERT INTO temp_api_current_items (itemId) VALUES (?)")
            for itemId in processedItemIds {
                try insertStatement.execute(arguments: [itemId])
            }

            let staleCount = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM item
                WHERE libraryId = ? AND itemId NOT IN (SELECT itemId FROM temp_api_current_items)
                """,
                arguments: [libraryId]
            ) ?? 0

            try db.execute(
                sql: "DELETE FROM folderItem WHERE libraryId = ? AND itemId NOT IN (SELECT itemId FROM temp_api_current_items)",
                arguments: [libraryId]
            )
            try db.execute(
                sql: "DELETE FROM item WHERE libraryId = ? AND itemId NOT IN (SELECT itemId FROM temp_api_current_items)",
                arguments: [libraryId]
            )

            return staleCount
        }
    }

    private func buildItem(libraryId: Int64, item: EagleItem) -> StoredItem {
        let name = item.name ?? ""
        let ext = item.ext ?? ""
        return StoredItem(
            libraryId: libraryId,
            itemId: item.id,
            name: name,
            nameForSort: nameForSort(from: name),
            size: item.size ?? 0,
            btime: item.btime ?? 0,
            mtime: item.mtime ?? 0,
            ext: ext,
            isDeleted: item.isDeleted ?? false,
            modificationTime: item.modificationTime ?? 0,
            height: item.height ?? 0,
            width: item.width ?? 0,
            lastModified: item.lastModified ?? 0,
            noThumbnail: item.noThumbnail ?? ItemFileType.isText(ext: ext),
            star: item.star ?? 0,
            duration: item.duration ?? 0,
            tags: item.tags ?? [],
            annotation: item.annotation ?? ""
        )
    }

    private func replaceFolderAssignments(db: Database, item: EagleItem, storedItem: StoredItem) throws {
        try db.execute(
            sql: "DELETE FROM folderItem WHERE libraryId = ? AND itemId = ?",
            arguments: [storedItem.libraryId, storedItem.itemId]
        )

        for folderId in Set(item.folders ?? []) {
            let folderItem = FolderItem(
                libraryId: storedItem.libraryId,
                folderId: folderId,
                itemId: storedItem.itemId,
                orderValue: item.order?[folderId] ?? String(storedItem.modificationTime)
            )
            try folderItem.insert(db)
        }
    }

    private func processFolder(
        db: Database,
        folder: EagleFolder,
        libraryId: Int64,
        parentId: String?,
        manualOrder: inout Int,
        processedFolderIds: inout Set<String>,
        existingFolderIds: Set<String>
    ) throws {
        guard let folderId = folder.id, !folderId.isEmpty else {
            return
        }
        guard !processedFolderIds.contains(folderId) else {
            return
        }

        let name = folder.name ?? ""
        let sortType = folderItemSortType(orderBy: folder.orderBy)
        let sortAscending = folder.sortIncrease ?? FolderItemSortOption.defaultValue.ascending
        var storedFolder = Folder(
            libraryId: libraryId,
            folderId: folderId,
            parentId: parentId,
            name: name,
            nameForSort: nameForSort(from: name),
            modificationTime: folder.modificationTime ?? 0,
            manualOrder: manualOrder,
            coverItemId: folder.coverId,
            sortType: sortType,
            sortAscending: sortAscending,
            sortModified: false
        )

        if existingFolderIds.contains(folderId) {
            try storedFolder.update(db, columns: ["parentId", "name", "nameForSort", "modificationTime", "manualOrder", "coverItemId"])
        } else {
            try storedFolder.insert(db)
        }

        processedFolderIds.insert(folderId)
        manualOrder += 1

        for child in folder.children ?? [] {
            try processFolder(
                db: db,
                folder: child,
                libraryId: libraryId,
                parentId: folderId,
                manualOrder: &manualOrder,
                processedFolderIds: &processedFolderIds,
                existingFolderIds: existingFolderIds
            )
        }
    }

    private func folderItemSortType(orderBy: String?) -> String {
        switch orderBy {
        case "GLOBAL":
            return FolderItemSortType.global.rawValue
        case "MANUAL":
            return FolderItemSortType.manual.rawValue
        case "IMPORT":
            return FolderItemSortType.dateAdded.rawValue
        case "NAME":
            return FolderItemSortType.title.rawValue
        case "RATING":
            return FolderItemSortType.rating.rawValue
        default:
            return FolderItemSortOption.defaultValue.type.rawValue
        }
    }

    private func nameForSort(from name: String) -> String {
        let regex = try! NSRegularExpression(pattern: "\\d+", options: [])
        let string = name as NSString
        let matches = regex.matches(in: name, options: [], range: NSRange(location: 0, length: string.length))
        var result = name
        var offset = 0

        for match in matches {
            let range = NSRange(location: match.range.location + offset, length: match.range.length)
            let matchedString = (result as NSString).substring(with: range)
            guard let number = Int(matchedString) else {
                continue
            }

            let paddedNumber = String(format: "%019d", number)
            result = (result as NSString).replacingCharacters(in: range, with: paddedNumber)
            offset += paddedNumber.count - match.range.length
        }

        return result
    }
}
