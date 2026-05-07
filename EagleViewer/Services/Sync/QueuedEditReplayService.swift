//
//  QueuedEditReplayService.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation
import GRDB

struct QueuedEditReplayService {
    private let operationRepository: SyncOperationRepository
    private let issueRepository: SyncIssueRepository
    private let apiClient: EagleAPIClient

    init(dbWriter: any DatabaseWriter, apiClient: EagleAPIClient) {
        operationRepository = SyncOperationRepository(dbWriter)
        issueRepository = SyncIssueRepository(dbWriter)
        self.apiClient = apiClient
    }

    func replayPendingEdits(for libraryId: Int64) async throws -> SyncOperationReplayResult {
        let pendingCount = try await operationRepository.operationCount(for: libraryId, states: [.pending, .applying])
        guard pendingCount > 0 else {
            return SyncOperationReplayResult()
        }

        try await operationRepository.resetInterruptedOperations(for: libraryId)
        let replayer = SyncOperationReplayer(
            queue: operationRepository,
            issueStore: issueRepository,
            apiClient: apiClient
        )
        let result = try await replayer.replayPendingOperations(for: libraryId)

        if result.hasIssues {
            try await issueRepository.markOpenIssues(
                for: libraryId,
                categories: [.queuedEdit, .conflict],
                as: .open
            )
        } else {
            try await issueRepository.markOpenIssues(
                for: libraryId,
                categories: [.queuedEdit, .conflict],
                as: .resolved
            )
        }

        return result
    }

    func retryFailedAndConflictedEdits(for libraryId: Int64) async throws -> SyncOperationReplayResult {
        _ = try await operationRepository.resetOperations(for: libraryId, states: [.failed, .conflicted, .applying])
        return try await replayPendingEdits(for: libraryId)
    }
}
