//
//  MetadataImportManager.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import Foundation
import GRDB
import OSLog
import SwiftUI

class MetadataImportManager: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0
    @Published var lastImportSummary: MetadataImporter.ImportRunSummary?
    
    private let metadataImporter = MetadataImporter()
    private var currentImportTask: Task<Void, Never>?
    private var currentImportRunID: UUID?
    
    func startImporting(
        library: Library,
        activeLibraryURL: URL?,
        dbWriter: DatabaseWriter,
        fullImport: Bool = false
    ) async {
        // Cancel any existing import task
        let importRunID = UUID()
        await MainActor.run {
            currentImportTask?.cancel()
            currentImportRunID = importRunID
        }
        
        // Start new import task
        let task = Task {
            let shouldStart = await MainActor.run {
                currentImportRunID == importRunID
            }
            guard shouldStart else { return }

            // Set importing state to true and reset progress
            await MainActor.run {
                isImporting = true
                importProgress = 0.0
                lastImportSummary = nil
            }
            
            var libraryURL: URL?
            var localURL: URL?
            var libraryAccessError: Error?
            var apiMediaSourceURL: URL?
            var apiMediaSourceAccessURL: URL?
            var apiMediaSourceFailureMessage: String?
            
            // Handle security-scoped resource for Eagle library access
            if library.useLocalStorage {
                do {
                    // Get local storage URL for image copying
                    localURL = try LocalImageStorageManager.shared.getLocalStorageURL(for: library.id)

                    // Temporarily access Eagle library for import
                    var isStale = false
                    libraryURL = try URL(
                        resolvingBookmarkData: library.bookmarkData,
                        options: [],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )

                    guard let libraryURL, libraryURL.startAccessingSecurityScopedResource() else {
                        throw LibraryFolderError.accessDenied
                    }
                } catch {
                    libraryAccessError = error
                    libraryURL = nil
                }
            } else {
                // Use the already-active library URL from LibraryFolderManager
                libraryURL = activeLibraryURL
            }

            if library.hasEagleAPIMediaFolder {
                do {
                    var isStale = false
                    let mediaSourceURL = try URL(
                        resolvingBookmarkData: library.bookmarkData,
                        options: [],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )

                    if isStale {
                        throw LibraryFolderError.bookmarkStale
                    }

                    guard mediaSourceURL.startAccessingSecurityScopedResource() else {
                        throw LibraryFolderError.accessDenied
                    }

                    apiMediaSourceURL = mediaSourceURL
                    apiMediaSourceAccessURL = mediaSourceURL
                } catch {
                    Logger.app.warning("Failed to open API media folder bookmark: \(error)")
                    apiMediaSourceFailureMessage = String(localized: "Metadata synced, but previews could not be cached because the selected Eagle library folder could not be opened. Re-select it in Settings.")
                }
            }
            
            // Ensure security-scoped resource is released when task ends
            defer {
                if localURL != nil, let libraryURL {
                    libraryURL.stopAccessingSecurityScopedResource()
                }

                if let apiMediaSourceAccessURL {
                    apiMediaSourceAccessURL.stopAccessingSecurityScopedResource()
                }
            }

            var importStatus: ImportStatus = .cancelled
            var importSummary = MetadataImporter.ImportRunSummary()
            var fatalErrorMessage: String?

            // Ensure importing state is reset and status is updated when task completes
            defer {
                let finalStatus = importStatus
                let finalSummary = importSummary
                let finalErrorMessage = fatalErrorMessage

                Task {
                    let shouldApply = await MainActor.run {
                        currentImportRunID == importRunID
                    }
                    guard shouldApply else { return }

                    // Update library import status first
                    do {
                        let finishedAt = Date()
                        try await dbWriter.write { db in
                            let errorMessage = finalErrorMessage ?? finalSummary.shortFailureDescription
                            var sql = """
                            UPDATE library
                            SET lastImportStatus = ?,
                                lastImportFailureCount = ?,
                                lastImportError = ?,
                                lastImportFinishedAt = ?
                            """
                            var arguments: StatementArguments = [
                                finalStatus.rawValue,
                                finalSummary.failureCount,
                                finalStatus == .success ? nil : errorMessage,
                                finishedAt
                            ]

                            if finalStatus.isSuccessful {
                                sql += ", lastSuccessfulImportAt = ?"
                                arguments += [finishedAt]
                            }

                            sql += " WHERE id = ?"
                            arguments += [library.id]
                            try db.execute(sql: sql, arguments: arguments)
                        }

                        let issues = ImportIssueMapper.issues(
                            libraryId: library.id,
                            status: finalStatus,
                            summary: finalSummary,
                            fatalErrorMessage: finalErrorMessage,
                            finishedAt: finishedAt
                        )
                        let syncIssueRepository = SyncIssueRepository(dbWriter)
                        try await syncIssueRepository.replaceOpenImportIssues(for: library.id, with: issues)
                    } catch {
                        Logger.app.warning("Failed to update import diagnostics: \(error)")
                    }
                    
                    // Then reset the importing state on main thread
                    await MainActor.run {
                        guard currentImportRunID == importRunID else { return }
                        lastImportSummary = finalSummary
                        isImporting = false
                        currentImportTask = nil
                        currentImportRunID = nil
                    }
                }
            }

            if let libraryAccessError {
                importStatus = .failed
                fatalErrorMessage = libraryAccessError.localizedDescription
                return
            }

            if library.isEagleAPISource {
                do {
                    try Task.checkCancellation()

                    guard let configuration = library.eagleAPIConfiguration else {
                        importStatus = .failed
                        fatalErrorMessage = String(localized: "Eagle API connection details are incomplete.")
                        return
                    }

                    let source = EagleAPILibrarySource(
                        library: library,
                        apiClient: EagleAPIClient(configuration: configuration)
                    )
                    let result = try await source.synchronize(
                        library: library,
                        dbWriter: dbWriter,
                        localMediaURL: activeLibraryURL,
                        mediaSourceURL: apiMediaSourceURL,
                        mediaSourceFailureMessage: apiMediaSourceFailureMessage,
                        progressHandler: { progress in
                            await MainActor.run {
                                self.importProgress = progress
                            }
                        }
                    )
                    let replayer = SyncOperationReplayer(
                        queue: SyncOperationRepository(dbWriter),
                        issueStore: SyncIssueRepository(dbWriter),
                        apiClient: EagleAPIClient(configuration: configuration)
                    )
                    let replayResult = try await replayer.replayPendingOperations(for: library.id)

                    importSummary = MetadataImporter.ImportRunSummary(syncResult: result)
                    importSummary.appendReplayResult(replayResult)
                    importStatus = importSummary.hasFailures ? .partial : .success
                } catch {
                    if error is CancellationError {
                        Logger.app.info("Import task was cancelled")
                        importStatus = .cancelled
                    } else {
                        Logger.app.warning("Failed to import metadata from Eagle API: \(error)")
                        importStatus = .failed
                        fatalErrorMessage = error.localizedDescription
                    }
                }

                return
            }

            guard let libraryURL else {
                importStatus = .failed
                fatalErrorMessage = LibraryFolderError.invalidBookmark.localizedDescription
                return
            }
            
            do {
                // Check for cancellation before importing
                try Task.checkCancellation()
                
                // For full import, reset the modification timestamps to force reimport of all data
                if fullImport {
                    try await dbWriter.write { db in
                        try db.execute(
                            sql: """
                            UPDATE library
                            SET lastImportedFolderMTime = 0,
                                lastImportedItemMTime = 0,
                                lastImportStatus = ?,
                                lastImportError = NULL,
                                lastImportFailureCount = 0
                            WHERE id = ?
                            """,
                            arguments: [ImportStatus.none.rawValue, library.id]
                        )
                    }
                }
                
                // Import all metadata (folders and items) with optional local storage
                importSummary = try await metadataImporter.importAll(
                    dbWriter: dbWriter,
                    libraryId: library.id,
                    libraryUrl: libraryURL,
                    localUrl: localURL, // Pass local URL for image copying if useLocalStorage
                    progressHandler: { progress in
                        await MainActor.run {
                            self.importProgress = progress
                        }
                    }
                )
                
                importStatus = importSummary.hasFailures ? .partial : .success
            } catch {
                if error is CancellationError {
                    Logger.app.info("Import task was cancelled")
                    importStatus = .cancelled
                } else {
                    Logger.app.warning("Failed to import metadata: \(error)")
                    importStatus = .failed
                    fatalErrorMessage = error.localizedDescription
                }
            }
        }
        
        await MainActor.run {
            currentImportTask = task
        }
    }
    
    @MainActor
    func cancelImporting() {
        currentImportTask?.cancel()
        currentImportTask = nil
    }
}

private extension MetadataImporter.ImportRunSummary {
    init(syncResult: LibrarySyncResult) {
        self.init()
        updatedItemCount = syncResult.updatedItemCount
        deletedItemCount = syncResult.deletedItemCount

        if syncResult.failureCount > 0 || syncResult.latestIssueMessage != nil {
            let message = syncResult.latestIssueMessage
                ?? String(localized: "\(syncResult.failureCount) Eagle API records could not sync.")
            failedItems = [
                MetadataImporter.ImportItemFailure(
                    itemId: "",
                    operation: String(localized: "Eagle API Sync"),
                    message: message
                ),
            ]
        }
    }

    mutating func appendReplayResult(_ replayResult: SyncOperationReplayResult) {
        guard replayResult.hasIssues else {
            return
        }

        failedItems.append(MetadataImporter.ImportItemFailure(
            itemId: "",
            operation: String(localized: "Queued Edits"),
            message: String(localized: "\(replayResult.failedCount) edits failed and \(replayResult.conflictedCount) edits need review.")
        ))
    }
}
