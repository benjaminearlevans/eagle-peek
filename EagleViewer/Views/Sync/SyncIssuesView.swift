//
//  SyncIssuesView.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import GRDBQuery
import SwiftUI

struct SyncIssuesView: View {
    @Environment(\.library) private var library
    @Environment(\.repositories) private var repositories
    @EnvironmentObject private var metadataImportManager: MetadataImportManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    @Query(SyncIssuesRequest(libraryId: nil)) private var issues: [SyncIssue]
    @State private var isRetryingQueuedEdits = false

    var body: some View {
        List {
            statusSection

            if issues.isEmpty {
                emptySection
            } else {
                Section("Open Issues") {
                    ForEach(issues) { issue in
                        SyncIssueRow(issue: issue)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Mark Resolved") {
                                    markIssue(issue, as: .resolved)
                                }
                                .tint(AppTheme.Status.success)

                                Button("Ignore") {
                                    markIssue(issue, as: .ignored)
                                }
                                .tint(AppTheme.Status.neutral)
                            }
                    }
                }
            }

            recoverySection
        }
        .navigationTitle("Sync Issues")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: library.id, initial: true) {
            $issues.libraryId.wrappedValue = library.id
        }
    }

    private var statusSection: some View {
        Section {
            SyncStatusSummaryView(
                library: library,
                isImporting: metadataImportManager.isImporting,
                progress: metadataImportManager.importProgress
            )
        }
    }

    private var emptySection: some View {
        Section {
            ContentUnavailableView {
                Label("No Open Sync Issues", systemImage: "checkmark.circle")
            } description: {
                Text(emptyMessage)
            }
        }
    }

    private var recoverySection: some View {
        Section("Recovery") {
            if metadataImportManager.isImporting {
                Button("Stop Syncing", role: .destructive) {
                    metadataImportManager.cancelImporting()
                }
            } else {
                Button {
                    startImporting(fullImport: false)
                } label: {
                    Label("Retry Sync", systemImage: "arrow.trianglehead.clockwise")
                }

                Button {
                    startImporting(fullImport: true)
                } label: {
                    Label("Full Resync", systemImage: "arrow.clockwise.circle")
                }

                if canRetryQueuedEdits {
                    Button {
                        retryQueuedEdits()
                    } label: {
                        Label("Retry Queued Edits", systemImage: "arrow.uturn.forward.circle")
                    }
                    .disabled(isRetryingQueuedEdits)
                }
            }

            Label(recoveryTip, systemImage: "lightbulb")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyMessage: String {
        switch library.lastImportStatus {
        case .success:
            return String(localized: "The latest sync completed successfully.")
        case .none:
            return String(localized: "Run sync to check this library.")
        case .partial, .failed, .cancelled:
            return String(localized: "No detailed issues are open. Retry sync if the library still looks incomplete.")
        }
    }

    private var recoveryTip: String {
        if library.isEagleAPISource {
            return String(localized: "For API libraries, keep Eagle Desktop running and retry queued edits after the connection is restored.")
        }

        if library.useLocalStorage {
            return String(localized: "For local libraries, keep the Eagle library folder available until sync finishes.")
        }

        return String(localized: "If folder access was interrupted, retry sync first. Use Full Resync only when items still look stale.")
    }

    private var canRetryQueuedEdits: Bool {
        guard library.eagleAPIConfiguration != nil else {
            return false
        }

        return issues.contains { issue in
            issue.category == .queuedEdit || issue.category == .conflict
        }
    }

    private func startImporting(fullImport: Bool) {
        Task {
            _ = try? await libraryFolderManager.getActiveLibraryURL()
            await metadataImportManager.startImporting(
                library: library,
                activeLibraryURL: libraryFolderManager.activeLibraryURL,
                dbWriter: repositories.dbWriter,
                fullImport: fullImport
            )
        }
    }

    private func markIssue(_ issue: SyncIssue, as state: SyncIssueResolutionState) {
        Task {
            try? await repositories.syncIssue.markIssue(id: issue.id, as: state)
        }
    }

    private func retryQueuedEdits() {
        guard let configuration = library.eagleAPIConfiguration else {
            return
        }

        isRetryingQueuedEdits = true
        Task {
            do {
                try await repositories.syncIssue.markOpenIssues(
                    for: library.id,
                    categories: [.queuedEdit, .conflict],
                    as: .retrying
                )
                let service = QueuedEditReplayService(
                    dbWriter: repositories.dbWriter,
                    apiClient: EagleAPIClient(configuration: configuration)
                )
                _ = try await service.retryFailedAndConflictedEdits(for: library.id)
            } catch {
                try? await repositories.syncIssue.save(SyncIssue(
                    libraryId: library.id,
                    category: .queuedEdit,
                    severity: .error,
                    title: String(localized: "Queued edit retry failed"),
                    message: error.localizedDescription,
                    recoverySuggestion: String(localized: "Check the connection to Eagle Desktop, then retry queued edits.")
                ))
            }

            await MainActor.run {
                isRetryingQueuedEdits = false
            }
        }
    }
}

private struct SyncIssueRow: View {
    let issue: SyncIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.headline)
                    .foregroundStyle(color)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(issue.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            if let itemId = issue.itemId, !itemId.isEmpty {
                Label(itemId, systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let recoverySuggestion = issue.recoverySuggestion, !recoverySuggestion.isEmpty {
                Label(recoverySuggestion, systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch issue.severity {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch issue.severity {
        case .info:
            return AppTheme.Status.neutral
        case .warning:
            return AppTheme.Status.warning
        case .error:
            return AppTheme.Status.critical
        }
    }
}
