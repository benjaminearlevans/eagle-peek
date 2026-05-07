//
//  ItemEditingService.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation
import GRDB

struct ItemEditingService {
    private struct QueuedItemEdit {
        let operation: SyncOperation
        let updateRequest: EagleItemUpdateRequest
    }

    private let dbWriter: any DatabaseWriter
    private let apiClient: EagleAPIClient?
    private let operationEncoder: SyncOperationEncoder

    init(
        dbWriter: any DatabaseWriter,
        apiClient: EagleAPIClient? = nil,
        operationEncoder: SyncOperationEncoder = SyncOperationEncoder()
    ) {
        self.dbWriter = dbWriter
        self.apiClient = apiClient
        self.operationEncoder = operationEncoder
    }

    func setRating(itemId: Item.ID, rating: Int) async throws {
        try await updateItem(itemId: itemId) { item in
            item.star = min(max(rating, 0), 5)
            return EagleItemUpdateRequest(id: item.itemId, star: item.star)
        }
    }

    func replaceTags(itemId: Item.ID, tags: [String]) async throws {
        let normalizedTags = normalized(tags)
        try await updateItem(itemId: itemId) { item in
            item.tags = normalizedTags
            return EagleItemUpdateRequest(id: item.itemId, tags: normalizedTags)
        }
    }

    func updateAnnotation(itemId: Item.ID, annotation: String) async throws {
        try await updateItem(itemId: itemId) { item in
            item.annotation = annotation
            return EagleItemUpdateRequest(id: item.itemId, annotation: annotation)
        }
    }

    private func updateItem(
        itemId: Item.ID,
        mutation: (inout StoredItem) throws -> EagleItemUpdateRequest
    ) async throws {
        let edit = try await dbWriter.write { db in
            guard var item = try StoredItem
                .filter(Column("libraryId") == itemId.libraryId)
                .filter(Column("itemId") == itemId.itemId)
                .fetchOne(db)
            else {
                throw ItemEditingError.itemNotFound
            }

            let baselineModificationTime = item.modificationTime
            let updateRequest = try mutation(&item)
            item.modificationTime = Self.localModificationTime()
            try item.update(db)

            let operation = SyncOperation(
                libraryId: item.libraryId,
                itemId: item.itemId,
                kind: .updateItem,
                payload: try operationEncoder.encodeUpdateItem(updateRequest),
                baselineModificationTime: baselineModificationTime
            )
            try SyncOperationRepository.insert(operation, db: db)
            return QueuedItemEdit(operation: operation, updateRequest: updateRequest)
        }

        guard let apiClient else {
            return
        }

        try await apiClient.updateItem(edit.updateRequest)
        try await SyncOperationRepository(dbWriter).removeOperation(id: edit.operation.id)
    }

    private func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty else {
                return nil
            }

            let key = trimmedTag.lowercased()
            guard !seen.contains(key) else {
                return nil
            }

            seen.insert(key)
            return trimmedTag
        }
    }

    private static func localModificationTime() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}

enum ItemEditingError: LocalizedError, Equatable {
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return String(localized: "Item could not be found.")
        }
    }
}
