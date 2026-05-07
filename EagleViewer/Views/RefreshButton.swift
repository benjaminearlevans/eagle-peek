//
//  RefreshButton.swift
//  EagleViewer
//
//  Created on 2025/09/14
//

import SwiftUI

struct RefreshButton: View {
    @Environment(\.library) private var library
    @Environment(\.repositories) private var repositories
    @EnvironmentObject private var metadataImportManager: MetadataImportManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager

    var body: some View {
        if libraryFolderManager.accessState == .opening ||
            // importProgress == 0  while establishing folder access if library is local
            (metadataImportManager.isImporting && metadataImportManager.importProgress == 0)
        {
            ProgressView()
        } else if metadataImportManager.isImporting {
            Menu {
                Button("Stop Syncing", role: .destructive) {
                    metadataImportManager.cancelImporting()
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)

                    Circle()
                        .trim(from: 0, to: metadataImportManager.importProgress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))

                    Text(verbatim: "\(Int(metadataImportManager.importProgress * 100))")
                        .font(.system(size: 8, weight: .medium))
                }
            }
        } else {
            Menu {
                Button("Sync New & Modified") {
                    startImporting(fullImport: false)
                }
                Button("Full Resync") {
                    startImporting(fullImport: true)
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.trianglehead.clockwise")
                        .foregroundColor(Color.primary)

                    if shouldShowAttentionBadge {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(attentionColor)
                            .background(Color(.systemBackground), in: Circle())
                            .offset(x: 6, y: -6)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(refreshAccessibilityLabel)
            }
            // iOS 26 bug
//            primaryAction: {
//                startImporting(fullImport: false)
//            }
        }
    }

    private func startImporting(fullImport: Bool) {
        Task {
            // establish folder access if not yet
            _ = try? await libraryFolderManager.getActiveLibraryURL()
            await metadataImportManager.startImporting(
                library: library,
                activeLibraryURL: libraryFolderManager.activeLibraryURL,
                dbWriter: repositories.dbWriter,
                fullImport: fullImport
            )
        }
    }

    private var shouldShowAttentionBadge: Bool {
        switch library.lastImportStatus {
        case .partial, .failed, .cancelled:
            return true
        case .none, .success:
            return false
        }
    }

    private var attentionColor: Color {
        switch library.lastImportStatus {
        case .failed:
            return .red
        case .partial, .cancelled:
            return .orange
        case .none, .success:
            return .secondary
        }
    }

    private var refreshAccessibilityLabel: String {
        switch library.lastImportStatus {
        case .partial:
            return String(localized: "Sync menu, last sync completed with issues")
        case .failed:
            return String(localized: "Sync menu, last sync failed")
        case .cancelled:
            return String(localized: "Sync menu, last sync stopped")
        case .none, .success:
            return String(localized: "Sync menu")
        }
    }
}
