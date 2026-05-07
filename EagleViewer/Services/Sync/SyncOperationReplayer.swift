//
//  SyncOperationReplayer.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

struct SyncOperationReplayResult: Equatable {
    var appliedCount = 0
    var failedCount = 0
    var conflictedCount = 0

    var hasIssues: Bool {
        failedCount > 0 || conflictedCount > 0
    }
}

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

    func replayPendingOperations(for libraryId: Int64) async throws -> SyncOperationReplayResult {
        let operations = try await queue.pendingOperations(for: libraryId)
        var result = SyncOperationReplayResult()

        for operation in operations {
            try Task.checkCancellation()
            switch try await replay(operation) {
            case .applied:
                result.appliedCount += 1
            case .failed:
                result.failedCount += 1
            case .conflicted:
                result.conflictedCount += 1
            }
        }

        return result
    }

    private func replay(_ operation: SyncOperation) async throws -> ReplayOutcome {
        var applyingOperation = operation
        applyingOperation.state = .applying
        applyingOperation.updatedAt = Date()
        applyingOperation.failureMessage = nil
        try await queue.update(applyingOperation)

        do {
            if try await hasConflict(operation) {
                try await markConflicted(operation, message: String(localized: "Desktop item changed before queued edit synced."))
                return .conflicted
            }

            try await apply(operation)
            try await queue.removeOperation(id: operation.id)
            return .applied
        } catch {
            if error is CancellationError {
                throw error
            }

            try await markFailed(operation, message: error.localizedDescription)
            return .failed
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

private enum ReplayOutcome {
    case applied
    case failed
    case conflicted
}
