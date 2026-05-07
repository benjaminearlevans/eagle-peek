//
//  EagleAPIMediaCache.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation
import OSLog

enum EagleAPIMediaCacheSetup {
    case available(EagleAPIMediaCache)
    case failed(String)
}

struct EagleAPIMediaCache {
    private let sourceLibraryURL: URL?
    private let destinationLibraryURL: URL
    private let sourceUnavailableMessage: String?
    private let fileManager: FileManager

    init(
        sourceLibraryURL: URL?,
        destinationLibraryURL: URL,
        sourceUnavailableMessage: String? = nil,
        fileManager: FileManager = .default
    ) {
        self.sourceLibraryURL = sourceLibraryURL
        self.destinationLibraryURL = destinationLibraryURL
        self.sourceUnavailableMessage = sourceUnavailableMessage
        self.fileManager = fileManager
    }

    func unavailableResult() -> LibrarySyncResult? {
        guard let sourceLibraryURL else {
            return unavailableResult(
                message: sourceUnavailableMessage
                    ?? String(localized: "Metadata synced, but previews could not be cached because Eagle did not report a library folder path.")
            )
        }

        let imagesURL = sourceLibraryURL.appending(path: "images", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: imagesURL.path) else {
            return unavailableResult(
                message: sourceUnavailableMessage
                    ?? String(localized: "Metadata synced, but previews could not be cached because this device cannot read the Eagle library files. The Eagle Web API exposes metadata and edits, but not image bytes.")
            )
        }

        return nil
    }

    func cachePreviews(for items: [StoredItem]) async -> LibrarySyncResult {
        var cachedCount = 0
        var failureCount = 0
        var latestIssueMessage: String?

        for item in items where !item.isTextFile {
            do {
                if try await cachePreview(for: item) {
                    cachedCount += 1
                }
            } catch {
                failureCount += 1
                latestIssueMessage = String(localized: "Preview cache failed for \(item.name): \(error.localizedDescription)")
                Logger.app.warning("Failed to cache API preview for \(item.itemId): \(error)")
            }
        }

        return LibrarySyncResult(
            updatedItemCount: 0,
            deletedItemCount: 0,
            failureCount: failureCount,
            latestIssueMessage: latestIssueMessage ?? (failureCount > 0 ? String(localized: "\(failureCount) API preview files could not be cached.") : nil)
        )
    }

    private func cachePreview(for item: StoredItem) async throws -> Bool {
        guard let sourceLibraryURL else {
            throw EagleAPIMediaCacheError.sourceUnavailable
        }

        let sourcePreviewURL = sourceLibraryURL.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
        let destinationPreviewURL = destinationLibraryURL.appending(path: item.thumbnailPath, directoryHint: .notDirectory)

        if await CloudFile.fileExists(at: sourcePreviewURL) {
            return try await copyIfNeeded(from: sourcePreviewURL, to: destinationPreviewURL)
        }

        guard item.noThumbnail == false else {
            throw EagleAPIMediaCacheError.fileNotFound(item.thumbnailPath)
        }

        let sourceOriginalURL = sourceLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
        guard await CloudFile.fileExists(at: sourceOriginalURL) else {
            throw EagleAPIMediaCacheError.fileNotFound(item.imagePath)
        }

        return try await copyIfNeeded(from: sourceOriginalURL, to: destinationPreviewURL)
    }

    private func copyIfNeeded(from sourceURL: URL, to destinationURL: URL) async throws -> Bool {
        if !shouldCopy(from: sourceURL, to: destinationURL) {
            return false
        }

        let destinationParent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        try await CloudFile.ensureMaterialized(at: sourceURL, timeout: 60)
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

        return true
    }

    private func shouldCopy(from sourceURL: URL, to destinationURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return true
        }

        let sourceModifiedAt = try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let destinationModifiedAt = try? destinationURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        guard let sourceModifiedAt, let destinationModifiedAt else {
            return true
        }

        return sourceModifiedAt > destinationModifiedAt
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
            throw EagleAPIMediaCacheError.insufficientDiskSpace(required: requiredCapacity, available: availableCapacity)
        }
    }

    private func unavailableResult(message: String) -> LibrarySyncResult {
        LibrarySyncResult(
            updatedItemCount: 0,
            deletedItemCount: 0,
            failureCount: 1,
            latestIssueMessage: message
        )
    }
}

enum EagleAPIMediaCacheError: LocalizedError {
    case sourceUnavailable
    case fileNotFound(String)
    case insufficientDiskSpace(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            return String(localized: "Eagle library files are unavailable on this device.")
        case .fileNotFound(let path):
            return String(localized: "Missing media file: \(path)")
        case .insufficientDiskSpace(let required, let available):
            return String(localized: "Not enough free space to copy preview. Required \(required) bytes, available \(available) bytes.")
        }
    }
}
