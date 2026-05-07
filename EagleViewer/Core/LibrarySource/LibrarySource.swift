//
//  LibrarySource.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

enum LibrarySourceKind: String, Codable, Hashable {
    case directFolder
    case eagleAPI
    case offlineCache
}

struct LibrarySourceIdentity: Codable, Equatable, Hashable {
    let kind: LibrarySourceKind
    let libraryId: Int64?
    let displayName: String
    let isWritable: Bool

    init(kind: LibrarySourceKind, libraryId: Int64?, displayName: String, isWritable: Bool) {
        self.kind = kind
        self.libraryId = libraryId
        self.displayName = displayName
        self.isWritable = isWritable
    }
}

struct LibrarySyncResult: Codable, Equatable {
    var updatedItemCount: Int
    var deletedItemCount: Int
    var failureCount: Int
    var latestIssueMessage: String?

    static let empty = LibrarySyncResult(
        updatedItemCount: 0,
        deletedItemCount: 0,
        failureCount: 0,
        latestIssueMessage: nil
    )

    var hasFailures: Bool {
        failureCount > 0
    }
}

protocol LibrarySource {
    var identity: LibrarySourceIdentity { get }

    func synchronize(
        library: Library,
        activeLibraryURL: URL?,
        repositories: Repositories,
        fullSync: Bool,
        progressHandler: @escaping (Double) async -> Void
    ) async throws -> LibrarySyncResult
}
