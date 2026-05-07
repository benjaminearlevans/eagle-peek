//
//  MetadataImporter.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import Foundation
import GRDB
import OSLog

struct MetadataImporter {
    struct ImportItemFailure: Codable, Hashable {
        let itemId: String
        let operation: String
        let message: String
    }

    struct ImportRunSummary: Codable, Equatable {
        var updatedItemCount = 0
        var deletedItemCount = 0
        var failedItems: [ImportItemFailure] = []

        var failureCount: Int {
            failedItems.count
        }

        var hasFailures: Bool {
            !failedItems.isEmpty
        }

        var shortFailureDescription: String? {
            guard let firstFailure = failedItems.first else {
                return nil
            }

            if failedItems.count == 1 {
                return "\(firstFailure.operation): \(firstFailure.message)"
            }

            return String(localized: "\(failedItems.count) items could not sync. First issue: \(firstFailure.message)")
        }
    }

    private enum MetadataLoadResult {
        case success(itemId: String, metadata: ItemMetadataJSON)
        case failure(ImportItemFailure)
    }

    private enum ItemCopyResult {
        case success(itemId: String)
        case failure(ImportItemFailure)
    }

    private enum LocalImageCopyError: LocalizedError {
        case insufficientDiskSpace(required: Int64, available: Int64)

        var errorDescription: String? {
            switch self {
            case .insufficientDiskSpace(let required, let available):
                return String(localized: "Not enough free space to copy image. Required \(required) bytes, available \(available) bytes.")
            }
        }
    }

    /// Converts a title to Eagle's special sort format
    /// Extracts digit sequences and replaces them with left zero-padded 19-character values
    private func nameForSort(from name: String) -> String {
        let regex = try! NSRegularExpression(pattern: "\\d+", options: [])
        let nsString = name as NSString
        let matches = regex.matches(in: name, options: [], range: NSRange(location: 0, length: nsString.length))
        
        var result = name
        var offset = 0
        
        for match in matches {
            let range = NSRange(location: match.range.location + offset, length: match.range.length)
            let matchedString = (result as NSString).substring(with: range)
            
            // Convert to integer and back to get clean number
            if let number = Int(matchedString) {
                let paddedNumber = String(format: "%019d", number)
                result = (result as NSString).replacingCharacters(in: range, with: paddedNumber)
                offset += paddedNumber.count - match.range.length
            }
        }
        
        return result
    }

    struct MetadataJSON: Decodable {
        let folders: [FolderJSON]
        let modificationTime: Int64
    }
    
    struct FolderJSON: Decodable {
        let id: String?
        let name: String?
        let modificationTime: Int64?
        let children: [FolderJSON]?
        let orderBy: String?
        let sortIncrease: Bool?
        let coverId: String?
    }
    
    struct ItemMetadataJSON: Decodable {
        let name: String?
        let size: Int?
        let btime: Int64?
        let mtime: Int64?
        let ext: String?
        let isDeleted: Bool?
        let modificationTime: Int64?
        let height: Int?
        let width: Int?
        let lastModified: Int64?
        let noThumbnail: Bool?
        let star: Int?
        let duration: Double?
        let folders: [String]?
        let order: [String: String]?
        let tags: [String]?
        let annotation: String?
    }
    
    struct MTimeJSON: Decodable {
        var itemTimes: [String: Int64]
        let totalCount: Int64
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let dict = try container.decode([String: Int64].self)
            
            // Extract "all" key for total count
            self.totalCount = dict["all"] ?? 0
            
            // Remove "all" key and use remaining as itemTimes
            var times = dict
            times.removeValue(forKey: "all")
            self.itemTimes = times
        }
    }
    
    /// Import all data from Eagle library metadata (folders and items)
    /// - Parameters:
    ///   - dbWriter: Database writer for transaction management
    ///   - libraryId: ID of the library to import data for
    ///   - libraryUrl: Security-scoped URL to the Eagle library (must be already activated)
    ///   - localUrl: Optional URL to local storage for copying images (if useLocalStorage)
    ///   - progressHandler: Callback to report import progress (0.0 to 1.0)
    func importAll(
        dbWriter: DatabaseWriter,
        libraryId: Int64,
        libraryUrl: URL,
        localUrl: URL?,
        progressHandler: @escaping (Double) async -> Void
    ) async throws -> ImportRunSummary {
        // Import folders first (assuming folders are 10% of the work)
        try await importFolders(
            dbWriter: dbWriter,
            libraryId: libraryId,
            libraryUrl: libraryUrl
        )
        
        await progressHandler(0.1) // 10% done after folders
        
        try Task.checkCancellation()
        
        // Import items (90% of the work)
        return try await importItems(
            dbWriter: dbWriter,
            libraryId: libraryId,
            libraryUrl: libraryUrl,
            localUrl: localUrl,
            progressHandler: { itemProgress in
                // Convert item progress [0,1] to overall progress [0.1,1]
                await progressHandler(0.1 + 0.9 * itemProgress)
            }
        )
    }
    
    /// Import items from Eagle library metadata
    /// - Parameters:
    ///   - dbWriter: Database writer for transaction management
    ///   - libraryId: ID of the library to import items for
    ///   - libraryUrl: Security-scoped URL to the Eagle library (must be already activated)
    ///   - localUrl: Optional URL to local storage for copying images (if useLocalStorage)
    ///   - progressHandler: Callback to report import progress
    func importItems(
        dbWriter: DatabaseWriter,
        libraryId: Int64,
        libraryUrl: URL,
        localUrl: URL?,
        progressHandler: @escaping (Double) async -> Void
    ) async throws -> ImportRunSummary {
        Logger.app.debug("Starting item import for library \(libraryId)")
        var summary = ImportRunSummary()
        
        // Get the library's last imported item modification time and existing item IDs
        let (lastImportedItemMTime, existingItemIds) = try await dbWriter.read { db in
            let lastMTime = try Int64.fetchOne(
                db,
                sql: "SELECT lastImportedItemMTime FROM library WHERE id = ?",
                arguments: [libraryId]
            ) ?? 0
            
            let itemIds = try Set(String.fetchAll(
                db,
                sql: "SELECT itemId FROM item WHERE libraryId = ?",
                arguments: [libraryId]
            ))
            
            return (lastMTime, itemIds)
        }
        
        // Get all item times including those not in mtime.json
        let allItemTimes = try await getAllItemTimes(
            libraryUrl: libraryUrl,
            existingDbItemIds: existingItemIds
        )
        
        // Find items that need to be updated, sorted by modification time
        let itemsToUpdate = allItemTimes
            .filter { _, modificationTime in modificationTime > lastImportedItemMTime }
            .sorted { $0.value < $1.value }
            .map { $0.key }
        var lastSafeImportedItemMTime = lastImportedItemMTime
        var timestampAdvanceBlocked = false
        
        if !itemsToUpdate.isEmpty {
            Logger.app.debug("Updating \(itemsToUpdate.count) items")
            
            let totalItems = itemsToUpdate.count
            var processedItems = 0
            
            // Process items in batches, each in its own transaction
            let batchSize = localUrl == nil ? 100 : 10
            for batch in itemsToUpdate.chunks(ofSize: batchSize) {
                // Load metadata for all items in batch first
                let metadataResults = try await withThrowingTaskGroup(of: MetadataLoadResult.self) { group in
                    for itemId in batch {
                        group.addTask {
                            do {
                                let metadata = try await loadItemMetadata(libraryUrl: libraryUrl, itemId: itemId)
                                return .success(itemId: itemId, metadata: metadata)
                            } catch {
                                if error is CancellationError {
                                    throw error
                                }
                                return .failure(ImportItemFailure(
                                    itemId: itemId,
                                    operation: String(localized: "Read metadata"),
                                    message: error.localizedDescription
                                ))
                            }
                        }
                    }
                    
                    var results: [MetadataLoadResult] = []
                    for try await result in group {
                        results.append(result)
                    }
                    return results
                }

                var batchMetadata: [(itemId: String, metadata: ItemMetadataJSON)] = []
                for result in metadataResults {
                    switch result {
                    case .success(let itemId, let metadata):
                        batchMetadata.append((itemId: itemId, metadata: metadata))
                    case .failure(let failure):
                        summary.failedItems.append(failure)
                    }
                }
                
                // Build Item instances from metadata
                var batchItems: [(item: StoredItem, metadata: ItemMetadataJSON)] = batchMetadata.map { itemId, metadata in
                    let item = buildItem(libraryId: libraryId, itemId: itemId, metadata: metadata)
                    return (item: item, metadata: metadata)
                }
                
                // Copy images to local storage if localUrl provided
                if let localUrl = localUrl {
                    let copyResults = try await withThrowingTaskGroup(of: ItemCopyResult.self) { group in
                        for (item, _) in batchItems {
                            group.addTask {
                                do {
                                    try await copyItemImages(
                                        item: item,
                                        libraryUrl: libraryUrl,
                                        localUrl: localUrl
                                    )
                                    return .success(itemId: item.itemId)
                                } catch {
                                    if error is CancellationError {
                                        throw error
                                    }
                                    return .failure(ImportItemFailure(
                                        itemId: item.itemId,
                                        operation: String(localized: "Copy file"),
                                        message: error.localizedDescription
                                    ))
                                }
                            }
                        }
                        
                        var results: [ItemCopyResult] = []
                        for try await result in group {
                            results.append(result)
                        }
                        return results
                    }

                    var failedCopyItemIds = Set<String>()
                    for result in copyResults {
                        switch result {
                        case .success:
                            break
                        case .failure(let failure):
                            failedCopyItemIds.insert(failure.itemId)
                            summary.failedItems.append(failure)
                        }
                    }
                    batchItems.removeAll { failedCopyItemIds.contains($0.item.itemId) }
                }
                
                try Task.checkCancellation()
                
                let itemsForWrite = batchItems
                let (batchSuccessfulItemIds, dbFailures) = try await dbWriter.write { db -> (Set<String>, [ImportItemFailure]) in
                    var successfulItemIds = Set<String>()
                    var failures: [ImportItemFailure] = []

                    for (item, metadata) in itemsForWrite {
                        do {
                            try processItem(db: db, item: item, metadata: metadata, existingItemIds: existingItemIds)
                            successfulItemIds.insert(item.itemId)
                        } catch {
                            failures.append(ImportItemFailure(
                                itemId: item.itemId,
                                operation: String(localized: "Save metadata"),
                                message: error.localizedDescription
                            ))
                        }
                    }

                    return (successfulItemIds, failures)
                }
                summary.failedItems.append(contentsOf: dbFailures)
                summary.updatedItemCount += batchSuccessfulItemIds.count

                if !timestampAdvanceBlocked {
                    for itemId in batch {
                        guard let timestamp = allItemTimes[itemId], timestamp != Int64.max else {
                            continue
                        }

                        if batchSuccessfulItemIds.contains(itemId) {
                            lastSafeImportedItemMTime = max(lastSafeImportedItemMTime, timestamp)
                        } else {
                            timestampAdvanceBlocked = true
                            break
                        }
                    }
                }

                if lastSafeImportedItemMTime > lastImportedItemMTime {
                    let importedItemMTime = lastSafeImportedItemMTime
                    try await dbWriter.write { db in
                        try db.execute(
                            sql: "UPDATE library SET lastImportedItemMTime = ? WHERE id = ?",
                            arguments: [importedItemMTime, libraryId]
                        )
                    }
                }
                
                processedItems += batch.count
                // Report progress from 0 to 0.95 for items (reserve 5% for deletion check)
                let itemProgress = Double(processedItems) / Double(totalItems) * 0.95
                await progressHandler(itemProgress)
                
                // Check for task cancellation between batches
                try Task.checkCancellation()
            }
        } else {
            Logger.app.debug("Skip: No items need updating")
            // Report 95% when no items to update (reserve 5% for deletion check)
            await progressHandler(0.95)
        }
        
        // Determine if we need to check for deletions
        let shouldCheckDeletion: Bool
        if itemsToUpdate.isEmpty {
            // Check if item count has changed
            let currentItemCount = try await dbWriter.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item WHERE libraryId = ?", arguments: [libraryId]) ?? 0
            }
            shouldCheckDeletion = currentItemCount != allItemTimes.count
        } else {
            shouldCheckDeletion = true
        }
        
        // Final transaction for cleanup and timestamp update
        let finalImportedItemMTime = timestampAdvanceBlocked ? lastSafeImportedItemMTime : (allItemTimes.values.filter { $0 != Int64.max }.max() ?? 0)
        try await dbWriter.write { db in
            if shouldCheckDeletion {
                // Create temporary table for current item IDs
                try db.execute(sql: "DROP TABLE IF EXISTS temp_current_items")
                try db.execute(sql: "CREATE TEMPORARY TABLE temp_current_items (itemId TEXT)")
                
                // Insert all current item IDs using prepared statement
                let insertStatement = try db.makeStatement(sql: "INSERT INTO temp_current_items (itemId) VALUES (?)")
                for (itemId, _) in allItemTimes {
                    try insertStatement.execute(arguments: [itemId])
                }
                
                // Delete removed items and their related records
                try db.execute(
                    sql: "DELETE FROM folderItem WHERE libraryId = ? AND itemId NOT IN (SELECT itemId FROM temp_current_items)",
                    arguments: [libraryId]
                )
                try db.execute(sql: "DELETE FROM item WHERE libraryId = ? AND itemId NOT IN (SELECT itemId FROM temp_current_items)", arguments: [libraryId])
            }
            
            // Update library timestamp (exclude Int64.max values from items not in mtime.json)
            try db.execute(sql: "UPDATE library SET lastImportedItemMTime = ? WHERE id = ?", arguments: [finalImportedItemMTime, libraryId])
        }
        
        // Report completion after deletion check
        await progressHandler(1.0)
        
        Logger.app.debug("Item import completed")
        return summary
    }
    
    /// Get all item times from mtime.json and discover missing items if needed
    /// - Parameters:
    ///   - libraryUrl: Security-scoped URL to the Eagle library
    ///   - existingDbItemIds: Set of item IDs already in the database
    /// - Returns: Dictionary of all item IDs to their modification times
    ///           - New items (not in mtime.json or DB): assigned Int64.max to ensure import
    ///           - Items in DB but not in mtime.json: assigned 0 to preserve without re-import
    private func getAllItemTimes(
        libraryUrl: URL,
        existingDbItemIds: Set<String>
    ) async throws -> [String: Int64] {
        let mtimeURL = libraryUrl.appending(path: "mtime.json", directoryHint: .notDirectory)
        
        let data = try await CloudFile.fileData(at: mtimeURL)
        let mtimeData = try JSONDecoder().decode(MTimeJSON.self, from: data)
        
        // Only scan directory if counts don't match (indicating missing items)
        if mtimeData.totalCount != mtimeData.itemTimes.count {
            Logger.app.debug("Item count mismatch: total=\(mtimeData.totalCount), in mtime=\(mtimeData.itemTimes.count), scanning for missing items")
            return try await discoverAllItems(
                libraryUrl: libraryUrl,
                existingItemTimes: mtimeData.itemTimes,
                existingDbItemIds: existingDbItemIds
            )
        } else {
            return mtimeData.itemTimes
        }
    }
    
    /// Discover all item directories in the Eagle library and merge with existing mtime data
    /// - Parameters:
    ///   - libraryUrl: Security-scoped URL to the Eagle library
    ///   - existingItemTimes: Existing item modification times from mtime.json
    ///   - existingDbItemIds: Set of item IDs already in the database
    /// - Returns: Merged dictionary including all discovered items
    private func discoverAllItems(
        libraryUrl: URL,
        existingItemTimes: [String: Int64],
        existingDbItemIds: Set<String>
    ) async throws -> [String: Int64] {
        var allItemTimes = existingItemTimes
        let imagesURL = libraryUrl.appending(path: "images", directoryHint: .isDirectory)
        
        guard await CloudFile.fileExists(at: imagesURL) else {
            Logger.app.debug("Images directory does not exist at \(imagesURL.path)")
            return allItemTimes
        }
        
        let contents = try FileManager.default.contentsOfDirectory(at: imagesURL, includingPropertiesForKeys: nil)
        var missingItemsNew: [String] = []
        var missingItemsInDb: [String] = []
        
        for itemURL in contents {
            // Check if it's an .info directory
            if itemURL.lastPathComponent.hasSuffix(".info") {
                // Extract item ID (remove .info suffix)
                let itemId = String(itemURL.lastPathComponent.dropLast(5))
                
                // If this item is not in mtime data
                if allItemTimes[itemId] == nil {
                    if existingDbItemIds.contains(itemId) {
                        // Item exists in DB but not in mtime.json - preserve it with timestamp 0
                        missingItemsInDb.append(itemId)
                        allItemTimes[itemId] = 0
                    } else {
                        // Item is new (not in mtime.json or DB) - import it with max timestamp
                        missingItemsNew.append(itemId)
                        allItemTimes[itemId] = Int64.max
                    }
                }
            }
        }
        
        if !missingItemsNew.isEmpty {
            Logger.app.info("Found \(missingItemsNew.count) new items not in mtime.json or database, adding with max timestamp")
            Logger.app.debug("New items: \(missingItemsNew.joined(separator: ", "))")
        }
        
        if !missingItemsInDb.isEmpty {
            Logger.app.info("Found \(missingItemsInDb.count) items in database but not in mtime.json, preserving with timestamp 0")
            Logger.app.debug("Preserved items: \(missingItemsInDb.joined(separator: ", "))")
        }
        
        return allItemTimes
    }
    
    private func loadItemMetadata(
        libraryUrl: URL,
        itemId: String
    ) async throws -> ItemMetadataJSON {
        let metadataURL = libraryUrl
            .appending(path: "images/\(itemId).info/metadata.json", directoryHint: .notDirectory)
        
        let data = try await CloudFile.fileData(at: metadataURL)
        return try JSONDecoder().decode(ItemMetadataJSON.self, from: data)
    }
    
    private func buildItem(
        libraryId: Int64,
        itemId: String,
        metadata: ItemMetadataJSON
    ) -> StoredItem {
        let name = metadata.name ?? ""
        let ext = metadata.ext ?? ""
        let noThumbnail: Bool
        if let metadataNoThumbnail = metadata.noThumbnail {
            noThumbnail = metadataNoThumbnail
        } else if ItemFileType.isText(ext: ext) {
            noThumbnail = true
        } else {
            noThumbnail = false
        }
        return StoredItem(
            libraryId: libraryId,
            itemId: itemId,
            name: name,
            nameForSort: nameForSort(from: name),
            size: metadata.size ?? 0,
            btime: metadata.btime ?? 0,
            mtime: metadata.mtime ?? 0,
            ext: ext,
            isDeleted: metadata.isDeleted ?? false,
            modificationTime: metadata.modificationTime ?? 0,
            height: metadata.height ?? 0,
            width: metadata.width ?? 0,
            lastModified: metadata.lastModified ?? 0,
            noThumbnail: noThumbnail,
            star: metadata.star ?? 0,
            duration: metadata.duration ?? 0,
            tags: metadata.tags ?? [],
            annotation: metadata.annotation ?? ""
        )
    }
    
    private func copyItemImages(
        item: StoredItem,
        libraryUrl: URL,
        localUrl: URL
    ) async throws {
        // Copy main image file
        let sourceImagePath = libraryUrl.appending(path: item.imagePath, directoryHint: .notDirectory)
        let destImagePath = localUrl.appending(path: item.imagePath, directoryHint: .notDirectory)

        try await atomicallyCopyMaterializedFile(from: sourceImagePath, to: destImagePath)
        Logger.app.debug("Copied image: \(item.imagePath)")
        
        // Copy thumbnail if it exists and is different from main image
        if !item.noThumbnail {
            let sourceThumbnailPath = libraryUrl.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
            if await CloudFile.fileExists(at: sourceThumbnailPath) {
                let destThumbnailPath = localUrl.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
                try await atomicallyCopyMaterializedFile(from: sourceThumbnailPath, to: destThumbnailPath)
                Logger.app.debug("Copied thumbnail: \(item.thumbnailPath)")
            }
        }
    }

    private func atomicallyCopyMaterializedFile(from sourceURL: URL, to destinationURL: URL) async throws {
        let fileManager = FileManager.default
        let destinationParent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        try await CloudFile.ensureMaterialized(at: sourceURL)
        try ensureAvailableSpaceForCopy(from: sourceURL, toDirectory: destinationParent)

        let temporaryURL = destinationParent.appending(
            path: ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private func ensureAvailableSpaceForCopy(from sourceURL: URL, toDirectory destinationDirectory: URL) throws {
        let sourceSize = Int64((try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard sourceSize > 0 else {
            return
        }

        let availableCapacity = try destinationDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage ?? Int64.max
        let requiredCapacity = sourceSize + min(sourceSize, 50 * 1024 * 1024)
        guard availableCapacity >= requiredCapacity else {
            throw LocalImageCopyError.insufficientDiskSpace(required: requiredCapacity, available: availableCapacity)
        }
    }
    
    private func processItem(
        db: Database,
        item: StoredItem,
        metadata: ItemMetadataJSON,
        existingItemIds: Set<String> = []
    ) throws {
        // Use insert for new items, save for existing items
        var mutableItem = item
        if existingItemIds.contains(item.itemId) {
            try mutableItem.save(db)
        } else {
            try mutableItem.insert(db)
        }
        
        // Delete existing FolderItem records and create new ones
        try db.execute(sql: "DELETE FROM folderItem WHERE libraryId = ? AND itemId = ?", arguments: [item.libraryId, item.itemId])
        if let folders = metadata.folders {
            for folderId in folders {
                // Use order value from metadata if available, otherwise use modificationTime as default
                let orderValue = metadata.order?[folderId] ?? String(metadata.modificationTime ?? 0)
                
                let folderItem = FolderItem(
                    libraryId: item.libraryId,
                    folderId: folderId,
                    itemId: item.itemId,
                    orderValue: orderValue
                )
                try folderItem.insert(db)
            }
        }
    }
    
    /// Import folders from Eagle library metadata
    /// - Parameters:
    ///   - dbWriter: Database writer for transaction management
    ///   - libraryId: ID of the library to import folders for
    ///   - libraryUrl: Security-scoped URL to the Eagle library (must be already activated)
    func importFolders(
        dbWriter: DatabaseWriter,
        libraryId: Int64,
        libraryUrl: URL
    ) async throws {
        Logger.app.debug("Starting metadata import for library \(libraryId)")
        
        let metadataURL = libraryUrl.appending(path: "metadata.json", directoryHint: .notDirectory)
        
        let data = try await CloudFile.fileData(at: metadataURL)
        let metadata = try JSONDecoder().decode(MetadataJSON.self, from: data)
        
        try await dbWriter.write { db in
            // Get the library's last imported modification time
            let lastImportedModificationTime = try Int64.fetchOne(
                db,
                sql: "SELECT lastImportedFolderMTime FROM library WHERE id = ?",
                arguments: [libraryId]
            ) ?? 0
            
            // Skip if metadata hasn't changed
            guard metadata.modificationTime > lastImportedModificationTime else {
                Logger.app.debug("Skip: Metadata hasn't changed")
                return
            }
            
            let existingFolderIds = try Set(
                String.fetchAll(db, sql: "SELECT folderId FROM folder WHERE libraryId = ?", arguments: [libraryId])
            )
            
            var processedFolderIds = Set<String>()
            var manualOrder = 0
            
            for folderJSON in metadata.folders {
                try processFolder(
                    db: db,
                    folderJSON: folderJSON,
                    libraryId: libraryId,
                    parentId: nil,
                    manualOrder: &manualOrder,
                    processedFolderIds: &processedFolderIds,
                    existingFolderIds: existingFolderIds
                )
            }
            
            let foldersToDelete = existingFolderIds.subtracting(processedFolderIds)
            for folderId in foldersToDelete {
                // Delete related records first
                _ = try db.execute(
                    sql: "DELETE FROM folderItem WHERE libraryId = ? AND folderId = ?",
                    arguments: [libraryId, folderId]
                )
                _ = try db.execute(
                    sql: "DELETE FROM folder WHERE libraryId = ? AND folderId = ?",
                    arguments: [libraryId, folderId]
                )
            }
            
            // Update the library's last imported modification time
            _ = try db.execute(
                sql: "UPDATE library SET lastImportedFolderMTime = ? WHERE id = ?",
                arguments: [metadata.modificationTime, libraryId]
            )
            
            Logger.app.debug("Metadata import completed")
        }
    }
    
    private func processFolder(
        db: Database,
        folderJSON: FolderJSON,
        libraryId: Int64,
        parentId: String?,
        manualOrder: inout Int,
        processedFolderIds: inout Set<String>,
        existingFolderIds: Set<String>
    ) throws {
        // Skip folders with missing or empty IDs
        guard let folderId = folderJSON.id, !folderId.isEmpty else {
            Logger.app.debug("Skipping folder with missing or empty ID")
            return
        }
        
        let name = folderJSON.name ?? ""

        // Map Eagle's orderBy to our FolderItemSortType
        let sortType: String
        if let orderBy = folderJSON.orderBy {
            switch orderBy {
            case "GLOBAL":
                sortType = FolderItemSortType.global.rawValue
            case "MANUAL":
                sortType = FolderItemSortType.manual.rawValue
            case "IMPORT":
                sortType = FolderItemSortType.dateAdded.rawValue
            case "NAME":
                sortType = FolderItemSortType.title.rawValue
            case "RATING":
                sortType = FolderItemSortType.rating.rawValue
            default:
                // Unsupported orderBy value, use default
                sortType = FolderItemSortOption.defaultValue.type.rawValue
            }
        } else {
            sortType = FolderItemSortOption.defaultValue.type.rawValue
        }

        let sortAscending = folderJSON.sortIncrease ?? FolderItemSortOption.defaultValue.ascending

        var folder = Folder(
            libraryId: libraryId,
            folderId: folderId,
            parentId: parentId,
            name: name,
            nameForSort: nameForSort(from: name),
            modificationTime: folderJSON.modificationTime ?? 0,
            manualOrder: manualOrder,
            coverItemId: folderJSON.coverId,
            sortType: sortType,
            sortAscending: sortAscending,
            sortModified: false // Only set to true when user changes in our app
        )

        // Use save for existing folders, insert for new folders
        if existingFolderIds.contains(folderId) {
            // keep user setting fields: sortType and sortAscending
            try folder.update(db, columns: ["parentId", "name", "nameForSort", "modificationTime", "manualOrder", "coverItemId"])

            // Update sort settings from Eagle metadata only if user hasn't modified them
            _ = try Folder
                .filter(Column("libraryId") == libraryId)
                .filter(Column("folderId") == folderId)
                .filter(Column("sortModified") == false)
                .updateAll(db, [
                    Column("sortType").set(to: sortType),
                    Column("sortAscending").set(to: sortAscending)
                ])
        } else {
            try folder.insert(db)
        }
        processedFolderIds.insert(folderId)
        manualOrder += 1
        
        // Process children if they exist
        if let children = folderJSON.children {
            for childJSON in children {
                try processFolder(
                    db: db,
                    folderJSON: childJSON,
                    libraryId: libraryId,
                    parentId: folderId,
                    manualOrder: &manualOrder,
                    processedFolderIds: &processedFolderIds,
                    existingFolderIds: existingFolderIds
                )
            }
        }
    }
}

extension Array {
    func chunks(ofSize size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
