//
//  SyncOperationRepository.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation
import GRDB

struct SyncOperationRepository: SyncOperationQueue {
    private let dbWriter: any DatabaseWriter

    init(_ dbWriter: some DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    func enqueue(_ operation: SyncOperation) async throws {
        try await dbWriter.write { db in
            try SyncOperationRecord(operation: operation).insert(db)
        }
    }

    func pendingOperations(for libraryId: Int64) async throws -> [SyncOperation] {
        try await operations(for: libraryId, states: [.pending])
    }

    func operations(for libraryId: Int64, states: [SyncOperationState]) async throws -> [SyncOperation] {
        guard !states.isEmpty else {
            return []
        }

        let placeholders = Array(repeating: "?", count: states.count).joined(separator: ", ")
        var arguments: StatementArguments = [libraryId]
        arguments += StatementArguments(states.map(\.rawValue))

        let queryArguments = arguments
        return try await dbWriter.read { db in
            try SyncOperationRecord.fetchAll(
                db,
                sql: """
                SELECT *
                FROM syncOperation
                WHERE libraryId = ? AND state IN (\(placeholders))
                ORDER BY createdAt, id
                """,
                arguments: queryArguments
            ).map(\.operation)
        }
    }

    func update(_ operation: SyncOperation) async throws {
        try await dbWriter.write { db in
            try SyncOperationRecord(operation: operation).update(db)
        }
    }

    func removeOperation(id: UUID) async throws {
        try await dbWriter.write { db in
            _ = try SyncOperationRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func resetInterruptedOperations(for libraryId: Int64) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: """
                UPDATE syncOperation
                SET state = ?, updatedAt = ?
                WHERE libraryId = ? AND state = ?
                """,
                arguments: [
                    SyncOperationState.pending.rawValue,
                    Date(),
                    libraryId,
                    SyncOperationState.applying.rawValue,
                ]
            )
        }
    }
}

private struct SyncOperationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "syncOperation"

    var id: String
    var libraryId: Int64
    var itemId: String?
    var kind: SyncOperationKind
    var state: SyncOperationState
    var payload: Data
    var baselineModificationTime: Int64?
    var createdAt: Date
    var updatedAt: Date
    var failureMessage: String?

    init(operation: SyncOperation) {
        id = operation.id.uuidString
        libraryId = operation.libraryId
        itemId = operation.itemId
        kind = operation.kind
        state = operation.state
        payload = operation.payload
        baselineModificationTime = operation.baselineModificationTime
        createdAt = operation.createdAt
        updatedAt = operation.updatedAt
        failureMessage = operation.failureMessage
    }

    var operation: SyncOperation {
        SyncOperation(
            id: UUID(uuidString: id) ?? UUID(),
            libraryId: libraryId,
            itemId: itemId,
            kind: kind,
            state: state,
            payload: payload,
            baselineModificationTime: baselineModificationTime,
            createdAt: createdAt,
            updatedAt: updatedAt,
            failureMessage: failureMessage
        )
    }
}
