//
//  SyncOperationReplayer.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

struct SyncOperationReplayer {
    private let queue: SyncOperationQueue
    private let issueStore: SyncIssueStore
    private let apiClient: EagleAPIClient
    private let operationEncoder: SyncOperationEncoder

    init(
        queue: SyncOperationQueue,
        issueStore: SyncIssueStore,
        apiClient: EagleAPIClient,
        operationEncoder: SyncOperationEncoder = SyncOperationEncoder()
    ) {
        self.queue = queue
        self.issueStore = issueStore
        self.apiClient = apiClient
        self.operationEncoder = operationEncoder
    }

    func replayPendingOperations(for libraryId: Int64) async throws {
        let operations = try await queue.pendingOperations(for: libraryId)

        for operation in operations {
            try Task.checkCancellation()
            try await replay(operation)
        }
    }

    private func replay(_ operation: SyncOperation) async throws {
        var applyingOperation = operation
        applyingOperation.state = .applying
        applyingOperation.updatedAt = Date()
        applyingOperation.failureMessage = nil
        try await queue.update(applyingOperation)

        do {
            if try await hasConflict(operation) {
                try await markConflicted(operation, message: String(localized: "Desktop item changed before queued edit synced."))
                return
            }

            try await apply(operation)
            try await queue.removeOperation(id: operation.id)
        } catch {
            if error is CancellationError {
                throw error
            }

            try await markFailed(operation, message: error.localizedDescription)
        }
    }

    private func apply(_ operation: SyncOperation) async throws {
        switch operation.kind {
        case .updateItem:
            let request = try operationEncoder.decodeUpdateItem(from: operation.payload)
            try await apiClient.updateItem(request)
        case .addItem, .updateFolder, .createFolder, .updateTag, .mergeTag, .createSmartFolder, .updateSmartFolder:
            throw EagleAPIError.apiStatus(String(localized: "Queued operation is not supported yet."))
        }
    }

    private func hasConflict(_ operation: SyncOperation) async throws -> Bool {
        guard let itemId = operation.itemId,
              let baselineModificationTime = operation.baselineModificationTime
        else {
            return false
        }

        let page = try await apiClient.items(EagleItemGetRequest(
            offset: 0,
            limit: 1,
            fields: ["id", "modificationTime"],
            ids: [itemId]
        ))
        let serverModificationTime = page.data.first?.modificationTime ?? 0
        return serverModificationTime > baselineModificationTime
    }

    private func markFailed(_ operation: SyncOperation, message: String) async throws {
        var failedOperation = operation
        failedOperation.state = .failed
        failedOperation.failureMessage = message
        failedOperation.updatedAt = Date()
        try await queue.update(failedOperation)

        try await issueStore.save(SyncIssue(
            libraryId: operation.libraryId,
            itemId: operation.itemId,
            category: .queuedEdit,
            severity: .error,
            title: String(localized: "Queued edit failed"),
            message: message,
            recoverySuggestion: String(localized: "Check the connection to Eagle Desktop, then retry sync.")
        ))
    }

    private func markConflicted(_ operation: SyncOperation, message: String) async throws {
        var conflictedOperation = operation
        conflictedOperation.state = .conflicted
        conflictedOperation.failureMessage = message
        conflictedOperation.updatedAt = Date()
        try await queue.update(conflictedOperation)

        try await issueStore.save(SyncIssue(
            libraryId: operation.libraryId,
            itemId: operation.itemId,
            category: .conflict,
            severity: .warning,
            title: String(localized: "Queued edit needs review"),
            message: message,
            recoverySuggestion: String(localized: "Review the queued change before retrying.")
        ))
    }
}
