//
//  Library.swift
//  EagleViewer
//
//  Created on 2025/08/22
//

import Foundation
import GRDB

enum ImportStatus: String, Codable, CaseIterable {
    case none // Never imported
    case success // Last import was successful
    case partial // Last import finished with item-level failures
    case failed // Last import failed
    case cancelled // Last import was cancelled

    var displayText: String {
        switch self {
        case .none: return String(localized: "Not Synced")
        case .success: return String(localized: "Completed")
        case .partial: return String(localized: "Completed with Issues")
        case .failed: return String(localized: "Failed")
        case .cancelled: return String(localized: "Cancelled")
        }
    }

    var isSuccessful: Bool {
        switch self {
        case .success, .partial:
            return true
        case .none, .failed, .cancelled:
            return false
        }
    }
}

struct NewLibrary: Codable, FetchableRecord, PersistableRecord {
    static var databaseTableName: String { Library.databaseTableName }

    var name: String
    var bookmarkData: Data
    var sortOrder: Int
    var useLocalStorage: Bool
    var sourceKind: LibrarySourceKind = .directFolder
    var apiBaseURL: String?
    var apiToken: String?
    var apiLibraryPath: String?
}

struct Library: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    var id: Int64
    var name: String
    var bookmarkData: Data
    var sortOrder: Int
    var lastImportedFolderMTime: Int64
    var lastImportedItemMTime: Int64
    var lastImportStatus: ImportStatus
    var lastImportError: String?
    var lastImportFailureCount: Int
    var lastImportFinishedAt: Date?
    var lastSuccessfulImportAt: Date?
    var useLocalStorage: Bool
    var sourceKind: LibrarySourceKind
    var apiBaseURL: String?
    var apiToken: String?
    var apiLibraryPath: String?
}

extension Library {
    var isEagleAPISource: Bool {
        sourceKind == .eagleAPI || sourceKind == .eagleBridge
    }

    var isEagleBridgeSource: Bool {
        sourceKind == .eagleBridge
    }

    var hasEagleAPIMediaFolder: Bool {
        sourceKind == .eagleAPI && !bookmarkData.isEmpty
    }

    var eagleAPIConfiguration: EagleAPIConfiguration? {
        guard isEagleAPISource,
              let apiBaseURL,
              let baseURL = URL(string: apiBaseURL)
        else {
            return nil
        }

        return EagleAPIConfiguration(
            baseURL: baseURL,
            token: apiToken,
            authentication: sourceKind == .eagleBridge ? .bearerToken : .queryToken
        )
    }

    var eagleAPILibraryURL: URL? {
        guard let apiLibraryPath, !apiLibraryPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: apiLibraryPath, isDirectory: true)
    }

    var eagleBridgeMediaBaseURL: URL? {
        guard sourceKind == .eagleBridge,
              let apiBaseURL,
              let baseURL = URL(string: apiBaseURL)
        else {
            return nil
        }

        let apiRoot = EagleAPIConfiguration(baseURL: baseURL).normalizedBaseURL
        let baseString = apiRoot.absoluteString
        if baseString.hasSuffix("/api/v2/") {
            return URL(string: String(baseString.dropLast("/api/v2/".count)) + "/media/v1/")
        }

        return URL(string: baseString)?.deletingLastPathComponent().deletingLastPathComponent().appending(path: "media/v1/", directoryHint: .isDirectory)
    }
}
