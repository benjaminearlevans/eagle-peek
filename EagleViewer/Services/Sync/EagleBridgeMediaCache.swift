//
//  EagleBridgeMediaCache.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation
import OSLog

struct EagleBridgeMediaCache {
    let mediaBaseURL: URL
    let deviceToken: String
    let destinationLibraryURL: URL
    var transport: EagleAPITransport = URLSession.shared
    var fileManager: FileManager = .default

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
                latestIssueMessage = String(localized: "Bridge preview cache failed for \(item.name): \(error.localizedDescription)")
                Logger.app.warning("Failed to cache bridge preview for \(item.itemId): \(error)")
            }
        }

        return LibrarySyncResult(
            updatedItemCount: cachedCount,
            deletedItemCount: 0,
            failureCount: failureCount,
            latestIssueMessage: latestIssueMessage ?? (failureCount > 0 ? String(localized: "\(failureCount) bridge preview files could not be cached.") : nil)
        )
    }

    private func cachePreview(for item: StoredItem) async throws -> Bool {
        let destinationPreviewURL = destinationLibraryURL.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: destinationPreviewURL.path) == false else {
            return false
        }

        let data = try await mediaData(itemId: item.itemId, variant: .thumbnail)
        try write(data, to: destinationPreviewURL)
        return true
    }

    private func mediaData(itemId: String, variant: MediaVariant) async throws -> Data {
        let url = mediaBaseURL
            .appending(path: "items", directoryHint: .isDirectory)
            .appending(path: itemId, directoryHint: .isDirectory)
            .appending(path: variant.rawValue, directoryHint: .notDirectory)
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EagleBridgeMediaCacheError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw EagleBridgeMediaCacheError.httpStatus(httpResponse.statusCode)
        }

        return data
    }

    private func write(_ data: Data, to destinationURL: URL) throws {
        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try ensureAvailableSpace(for: Int64(data.count), in: parentURL)

        let temporaryURL = parentURL.appending(
            path: ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try data.write(to: temporaryURL, options: .atomic)
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

    private func ensureAvailableSpace(for byteCount: Int64, in directoryURL: URL) throws {
        guard byteCount > 0 else {
            return
        }

        let availableCapacity = try directoryURL
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage ?? Int64.max
        let requiredCapacity = byteCount + min(byteCount, 50 * 1024 * 1024)
        guard availableCapacity >= requiredCapacity else {
            throw EagleBridgeMediaCacheError.insufficientDiskSpace(required: requiredCapacity, available: availableCapacity)
        }
    }
}

enum EagleBridgeMediaCacheError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case insufficientDiskSpace(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "Bridge media server returned an invalid response.")
        case .httpStatus(let statusCode):
            return String(localized: "Bridge media request failed with HTTP \(statusCode).")
        case .insufficientDiskSpace(let required, let available):
            return String(localized: "Not enough free space to cache preview. Required \(required) bytes, available \(available) bytes.")
        }
    }
}
