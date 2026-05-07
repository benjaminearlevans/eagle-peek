//
//  SyncIssueRepository.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation
import GRDB

struct SyncIssueRepository: SyncIssueStore {
    private let dbWriter: any DatabaseWriter

    init(_ dbWriter: some DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    func openIssues(for libraryId: Int64) async throws -> [SyncIssue] {
        try await dbWriter.read { db in
            try SyncIssueRecord.fetchOpenIssues(db, libraryId: libraryId)
        }
    }

    func issue(id: UUID) async throws -> SyncIssue? {
        try await dbWriter.read { db in
            try SyncIssueRecord.fetchOne(db, key: id.uuidString)?.syncIssue
        }
    }

    func save(_ issue: SyncIssue) async throws {
        try await dbWriter.write { db in
            try SyncIssueRecord(issue: issue).save(db)
        }
    }

    func markIssue(id: UUID, as state: SyncIssueResolutionState) async throws {
        try await dbWriter.write { db in
            try SyncIssueRecord.markIssue(db, id: id, as: state)
        }
    }

    func markOpenIssues(
        for libraryId: Int64,
        categories: [SyncIssueCategory],
        as state: SyncIssueResolutionState
    ) async throws {
        try await dbWriter.write { db in
            try SyncIssueRecord.markOpenIssues(db, libraryId: libraryId, categories: categories, as: state)
        }
    }

    func replaceOpenImportIssues(for libraryId: Int64, with issues: [SyncIssue]) async throws {
        try await dbWriter.write { db in
            try SyncIssueRecord.resolveOpenImportIssues(db, libraryId: libraryId)

            for issue in issues {
                try SyncIssueRecord(issue: issue).save(db)
            }
        }
    }
}

struct SyncIssueRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "syncIssue"

    var id: String
    var libraryId: Int64
    var itemId: String?
    var category: String
    var severity: String
    var title: String
    var message: String
    var recoverySuggestion: String?
    var resolutionState: String
    var createdAt: Date
    var updatedAt: Date

    init(issue: SyncIssue) {
        id = issue.id.uuidString
        libraryId = issue.libraryId
        itemId = issue.itemId
        category = issue.category.rawValue
        severity = issue.severity.rawValue
        title = issue.title
        message = issue.message
        recoverySuggestion = issue.recoverySuggestion
        resolutionState = issue.resolutionState.rawValue
        createdAt = issue.createdAt
        updatedAt = issue.updatedAt
    }

    var syncIssue: SyncIssue {
        SyncIssue(
            id: UUID(uuidString: id) ?? UUID(),
            libraryId: libraryId,
            itemId: itemId,
            category: SyncIssueCategory(rawValue: category) ?? .unknown,
            severity: SyncIssueSeverity(rawValue: severity) ?? .error,
            title: title,
            message: message,
            recoverySuggestion: recoverySuggestion,
            resolutionState: SyncIssueResolutionState(rawValue: resolutionState) ?? .open,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func fetchOpenIssues(_ db: Database, libraryId: Int64) throws -> [SyncIssue] {
        try SyncIssueRecord
            .filter(Column("libraryId") == libraryId)
            .filter(openStateFilter)
            .order(Column("updatedAt").desc)
            .fetchAll(db)
            .map(\.syncIssue)
    }

    static func markIssue(_ db: Database, id: UUID, as state: SyncIssueResolutionState) throws {
        try SyncIssueRecord
            .filter(Column("id") == id.uuidString)
            .updateAll(
                db,
                Column("resolutionState").set(to: state.rawValue),
                Column("updatedAt").set(to: Date())
            )
    }

    static func resolveOpenImportIssues(_ db: Database, libraryId: Int64) throws {
        try SyncIssueRecord
            .filter(Column("libraryId") == libraryId)
            .filter(openStateFilter)
            .filter(importCategoryFilter)
            .updateAll(
                db,
                Column("resolutionState").set(to: SyncIssueResolutionState.resolved.rawValue),
                Column("updatedAt").set(to: Date())
            )
    }

    static func markOpenIssues(
        _ db: Database,
        libraryId: Int64,
        categories: [SyncIssueCategory],
        as state: SyncIssueResolutionState
    ) throws {
        guard !categories.isEmpty else {
            return
        }

        try SyncIssueRecord
            .filter(Column("libraryId") == libraryId)
            .filter(openStateFilter)
            .filter(categories.map(\.rawValue).contains(Column("category")))
            .updateAll(
                db,
                Column("resolutionState").set(to: state.rawValue),
                Column("updatedAt").set(to: Date())
            )
    }

    private static var openStateFilter: SQLSpecificExpressible {
        [
            SyncIssueResolutionState.open.rawValue,
            SyncIssueResolutionState.retrying.rawValue,
        ].contains(Column("resolutionState"))
    }

    private static var importCategoryFilter: SQLSpecificExpressible {
        [
            SyncIssueCategory.connection.rawValue,
            SyncIssueCategory.importMetadata.rawValue,
            SyncIssueCategory.copyMedia.rawValue,
            SyncIssueCategory.storage.rawValue,
            SyncIssueCategory.unknown.rawValue,
        ].contains(Column("category"))
    }
}
