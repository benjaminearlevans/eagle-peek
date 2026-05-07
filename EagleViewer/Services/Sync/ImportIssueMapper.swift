//
//  ImportIssueMapper.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

enum ImportIssueMapper {
    static func issues(
        libraryId: Int64,
        status: ImportStatus,
        summary: MetadataImporter.ImportRunSummary,
        fatalErrorMessage: String?,
        finishedAt: Date = Date()
    ) -> [SyncIssue] {
        if status == .success {
            return []
        }

        if !summary.failedItems.isEmpty {
            return summary.failedItems.map { failure in
                itemIssue(libraryId: libraryId, failure: failure, date: finishedAt)
            }
        }

        guard let fatalErrorMessage, !fatalErrorMessage.isEmpty else {
            return []
        }

        return [
            SyncIssue(
                libraryId: libraryId,
                category: .connection,
                severity: .error,
                title: String(localized: "Sync could not finish"),
                message: fatalErrorMessage,
                recoverySuggestion: String(localized: "Check library folder access, confirm the Eagle library is available, then retry sync."),
                createdAt: finishedAt,
                updatedAt: finishedAt
            ),
        ]
    }

    private static func itemIssue(
        libraryId: Int64,
        failure: MetadataImporter.ImportItemFailure,
        date: Date
    ) -> SyncIssue {
        SyncIssue(
            libraryId: libraryId,
            itemId: failure.itemId,
            category: category(for: failure.operation),
            severity: .warning,
            title: String(localized: "\(failure.operation) failed"),
            message: failure.message,
            recoverySuggestion: recoverySuggestion(for: failure.operation),
            createdAt: date,
            updatedAt: date
        )
    }

    private static func category(for operation: String) -> SyncIssueCategory {
        let normalizedOperation = operation.lowercased()

        if normalizedOperation.contains("copy") {
            return .copyMedia
        }

        if normalizedOperation.contains("metadata") || normalizedOperation.contains("database") {
            return .importMetadata
        }

        if normalizedOperation.contains("space") || normalizedOperation.contains("storage") {
            return .storage
        }

        return .unknown
    }

    private static func recoverySuggestion(for operation: String) -> String {
        switch category(for: operation) {
        case .copyMedia, .storage:
            return String(localized: "Free storage if needed, confirm local media access, then run Sync New & Modified.")
        case .importMetadata:
            return String(localized: "Confirm the item still exists in the Eagle library, then run Sync New & Modified.")
        case .connection:
            return String(localized: "Check the connection to the Eagle library, then retry sync.")
        case .queuedEdit, .conflict:
            return String(localized: "Review the queued change before retrying.")
        case .unknown:
            return String(localized: "Run Sync New & Modified. If the issue returns, try Full Resync.")
        }
    }
}
