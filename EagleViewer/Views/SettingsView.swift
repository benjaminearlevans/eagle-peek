//
//  SettingsView.swift
//  EagleViewer
//
//  Created on 2025/08/26
//

import SwiftUI

struct SettingsView: View {
    enum Destination: Hashable {
        case folderSelect
        case apiMediaFolderSelect
        case syncIssues
    }

    let initialDestination: Destination?

    @Environment(\.library) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.repositories) private var repositories
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var metadataImportManager: MetadataImportManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    @State private var showingLibraries = false
    @State private var path = NavigationPath()
    @State private var didApplyInitialDestination = false

    init(initialDestination: Destination? = nil) {
        self.initialDestination = initialDestination
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Library") {
                    if library.isEagleAPISource {
                        LabeledContent("Metadata source") {
                            Text("Eagle API")
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent("API endpoint") {
                            Text(apiEndpointLabel)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        NavigationLink(value: Destination.apiMediaFolderSelect) {
                            LabeledContent("Media previews") {
                                if library.hasEagleAPIMediaFolder {
                                    Text("Configured")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Set Up")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }

                        Text("Eagle API syncs metadata and edits. Select the same .library folder through Files to cache image previews and make the viewer work offline.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink(value: Destination.folderSelect) {
                            LabeledContent("Eagle Library Folder") {
                                Text(library.name)
                            }
                        }

                        Toggle("Download images locally", isOn: .constant(library.useLocalStorage))
                            .disabled(true)
                    }

                    Button("Change Library...") {
                        showingLibraries = true
                    }
                    .foregroundColor(.accentColor)
                }

                Section("Sync") {
                    NavigationLink(value: Destination.syncIssues) {
                        Label {
                            LabeledContent("Sync Issues") {
                                syncIssueCountLabel
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(syncAttentionColor)
                        }
                    }

                    SyncStatusSummaryView(
                        library: library,
                        isImporting: metadataImportManager.isImporting,
                        progress: metadataImportManager.importProgress
                    )

                    if let lastSuccessfulImportAt = library.lastSuccessfulImportAt {
                        LabeledContent("Last successful sync") {
                            Text(lastSuccessfulImportAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let lastImportFinishedAt = library.lastImportFinishedAt {
                        LabeledContent("Last attempt") {
                            Text(lastImportFinishedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if library.lastImportFailureCount > 0 {
                        LabeledContent("Items with issues") {
                            Text(library.lastImportFailureCount.formatted())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let lastImportError = library.lastImportError, !lastImportError.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Latest sync issue", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(syncAttentionColor)

                            Text(lastImportError)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    if metadataImportManager.isImporting {
                        Button("Stop Syncing", role: .destructive) {
                            metadataImportManager.cancelImporting()
                        }
                    } else {
                        Button {
                            startImporting(fullImport: false)
                        } label: {
                            Label("Sync New & Modified", systemImage: "arrow.trianglehead.clockwise")
                        }
                        .foregroundColor(.accentColor)

                        Button {
                            startImporting(fullImport: true)
                        } label: {
                            Label("Full Resync", systemImage: "arrow.clockwise.circle")
                        }
                        .foregroundColor(.accentColor)
                    }

                    if !library.useLocalStorage && !library.isEagleAPISource && libraryFolderManager.accessState == .closed {
                        Label(
                            "Folder access is closed. Sync will try to reopen the saved library bookmark.",
                            systemImage: "folder.badge.questionmark"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .folderSelect:
                    LibraryFolderSelectView { name, bookmarkData in
                        updateLibraryFolder(name: name, bookmarkData: bookmarkData)
                    }
                case .apiMediaFolderSelect:
                    LibraryFolderSelectView { _, bookmarkData in
                        updateAPIMediaFolder(bookmarkData: bookmarkData)
                    }
                case .syncIssues:
                    SyncIssuesView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingLibraries) {
                LibrariesView()
            }
            .onAppear {
                applyInitialDestinationIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var syncIssueCountLabel: some View {
        if library.lastImportFailureCount > 0 {
            Text(library.lastImportFailureCount.formatted())
                .foregroundStyle(.secondary)
        } else {
            Text(library.lastImportStatus.displayText)
                .foregroundStyle(.secondary)
        }
    }

    private var syncAttentionColor: Color {
        switch library.lastImportStatus {
        case .partial, .cancelled:
            return AppTheme.Status.warning
        case .failed:
            return AppTheme.Status.critical
        case .none, .success:
            return AppTheme.Status.neutral
        }
    }

    private var apiEndpointLabel: String {
        guard let apiBaseURL = library.apiBaseURL,
              let url = URL(string: apiBaseURL)
        else {
            return String(localized: "Not configured")
        }

        if let host = url.host {
            return host
        }

        return apiBaseURL
    }

    private func applyInitialDestinationIfNeeded() {
        guard !didApplyInitialDestination, let initialDestination else {
            return
        }

        didApplyInitialDestination = true
        path.append(initialDestination)
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

    private func updateLibraryFolder(name: String, bookmarkData: Data) {
        Task {
            do {
                try await repositories.library.updateFolder(id: library.id, name: name, bookmarkData: bookmarkData)
                path = NavigationPath()
            } catch {
                // Handle error
            }
        }
    }

    private func updateAPIMediaFolder(bookmarkData: Data) {
        Task {
            do {
                let updatedLibrary = try await repositories.library.updateEagleAPIMediaFolder(
                    id: library.id,
                    bookmarkData: bookmarkData
                )
                let activeLibraryURL = await MainActor.run {
                    libraryFolderManager.updateCurrentLibrary(updatedLibrary)
                    path = NavigationPath()
                    return libraryFolderManager.activeLibraryURL
                }

                await metadataImportManager.startImporting(
                    library: updatedLibrary,
                    activeLibraryURL: activeLibraryURL,
                    dbWriter: repositories.dbWriter,
                    fullImport: true
                )
            } catch {
                // Existing settings actions fail silently; sync diagnostics surface import failures.
            }
        }
    }
}

struct SyncStatusSummaryView: View {
    let library: Library
    let isImporting: Bool
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusSymbolName)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.headline)

                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isImporting {
                HStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)

                    Text(verbatim: "\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sync progress")
                .accessibilityValue("\(Int(progress * 100)) percent")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        if isImporting {
            return String(localized: "Syncing")
        }

        return library.lastImportStatus.displayText
    }

    private var statusMessage: String {
        if isImporting {
            return String(localized: "Checking library changes and copying media safely.")
        }

        switch library.lastImportStatus {
        case .none:
            return String(localized: "This library has not synced yet.")
        case .success:
            if let lastSuccessfulImportAt = library.lastSuccessfulImportAt {
                return String(localized: "Up to date as of \(lastSuccessfulImportAt.formatted(date: .abbreviated, time: .shortened)).")
            }
            return String(localized: "The last sync completed successfully.")
        case .partial:
            return String(localized: "\(issueCountText) could not sync. Successful changes were still saved.")
        case .failed:
            return library.lastImportError ?? String(localized: "The last sync could not finish.")
        case .cancelled:
            return String(localized: "The last sync was stopped before it finished.")
        }
    }

    private var issueCountText: String {
        if library.lastImportFailureCount == 1 {
            return String(localized: "1 item")
        }

        return String(localized: "\(library.lastImportFailureCount) items")
    }

    private var statusSymbolName: String {
        if isImporting {
            return "arrow.trianglehead.2.clockwise.rotate.90"
        }

        switch library.lastImportStatus {
        case .none:
            return "icloud.slash"
        case .success:
            return "checkmark.circle.fill"
        case .partial:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .cancelled:
            return "pause.circle.fill"
        }
    }

    private var statusColor: Color {
        if isImporting {
            return .accentColor
        }

        switch library.lastImportStatus {
        case .none:
            return AppTheme.Status.neutral
        case .success:
            return AppTheme.Status.success
        case .partial, .cancelled:
            return AppTheme.Status.warning
        case .failed:
            return AppTheme.Status.critical
        }
    }
}

struct SyncStatusBanner: View {
    let library: Library

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint("Opens sync settings")
    }

    private var title: String {
        switch library.lastImportStatus {
        case .partial:
            return String(localized: "Sync completed with issues")
        case .failed:
            return String(localized: "Sync failed")
        case .cancelled:
            return String(localized: "Sync stopped")
        case .none, .success:
            return library.lastImportStatus.displayText
        }
    }

    private var message: String {
        switch library.lastImportStatus {
        case .partial:
            if library.lastImportFailureCount == 1 {
                return String(localized: "1 item needs attention. Tap for details and recovery.")
            }

            return String(localized: "\(library.lastImportFailureCount) items need attention. Tap for details and recovery.")
        case .failed:
            return library.lastImportError ?? String(localized: "Tap to review the latest issue and retry.")
        case .cancelled:
            return String(localized: "Tap to resume syncing when you are ready.")
        case .none, .success:
            return String(localized: "Tap to review sync settings.")
        }
    }

    private var symbolName: String {
        switch library.lastImportStatus {
        case .partial:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .cancelled:
            return "pause.circle.fill"
        case .none:
            return "icloud.slash"
        case .success:
            return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch library.lastImportStatus {
        case .partial, .cancelled:
            return AppTheme.Status.warning
        case .failed:
            return AppTheme.Status.critical
        case .none:
            return AppTheme.Status.neutral
        case .success:
            return AppTheme.Status.success
        }
    }
}

struct SyncProgressBanner: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Syncing library")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(String(localized: "\(Int(progress * 100))% complete"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Syncing library")
        .accessibilityValue(String(localized: "\(Int(progress * 100))% complete"))
        .accessibilityHint("Opens sync settings")
    }
}
