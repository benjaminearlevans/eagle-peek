//
//  ViewerPowerToolsMenu.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import SwiftUI
import UIKit

struct ViewerPowerToolsMenu: View {
    let item: Item
    let itemURL: URL?
    let isChromeHidden: Bool
    let navigationState: ViewerNavigationState
    let showInfo: () -> Void
    let toggleChrome: () -> Void
    let goToFirst: () -> Void
    let goToPrevious: () -> Void
    let goToNext: () -> Void
    let goToLast: () -> Void
    let showCopiedMessage: (String) -> Void

    var body: some View {
        Menu {
            Section {
                Button(action: showInfo) {
                    Label("Show Info", systemImage: "info.circle")
                }

                Button(action: toggleChrome) {
                    Label(isChromeHidden ? "Show Controls" : "Hide Controls", systemImage: "rectangle.expand.vertical")
                }
            }

            Section("Navigate") {
                Button(action: goToFirst) {
                    Label("First Item", systemImage: "backward.end")
                }
                .disabled(!navigationState.canGoPrevious)

                Button(action: goToPrevious) {
                    Label("Previous Item", systemImage: "chevron.left")
                }
                .disabled(!navigationState.canGoPrevious)

                Button(action: goToNext) {
                    Label("Next Item", systemImage: "chevron.right")
                }
                .disabled(!navigationState.canGoNext)

                Button(action: goToLast) {
                    Label("Last Item", systemImage: "forward.end")
                }
                .disabled(!navigationState.canGoNext)
            }

            Section("Copy") {
                Button(action: copyName) {
                    Label("Copy Name", systemImage: "doc.on.doc")
                }

                if itemURL != nil {
                    Button(action: copyFilePath) {
                        Label("Copy File Path", systemImage: "link")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(.primary)
        }
        .accessibilityLabel("Viewer actions")
    }

    private func copyName() {
        UIPasteboard.general.string = item.name
        notifyCopy(message: String(localized: "Name copied"))
    }

    private func copyFilePath() {
        guard let itemURL else {
            return
        }

        UIPasteboard.general.string = itemURL.path
        notifyCopy(message: String(localized: "File path copied"))
    }

    private func notifyCopy(message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showCopiedMessage(message)
    }
}
