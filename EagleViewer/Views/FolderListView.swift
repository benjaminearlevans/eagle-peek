//
//  FolderListView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB
import GRDBQuery
import SwiftUI

enum PlaceholderType {
    case none
    case search
    case `default`
}

struct FolderListView: View {
    let folders: [Folder]
    let placeholderType: PlaceholderType
    let onSelected: ((Folder) -> Void)?

    @EnvironmentObject private var navigationManager: NavigationManager

    init(folders: [Folder], placeholderType: PlaceholderType = .none, onSelected: ((Folder) -> Void)? = nil) {
        self.folders = folders
        self.placeholderType = placeholderType
        self.onSelected = onSelected
    }

    var body: some View {
        if folders.isEmpty && placeholderType != .none {
            switch placeholderType {
            case .search:
                NoResultsView()
            case .default:
                NoFolderView()
            case .none:
                EmptyView()
            }
        } else {
            AdaptiveGridView(isCollection: true) {
                ForEach(folders) { folder in
                    Button(action: {
                        onSelected?(folder)
                        navigationManager.path.append(.folder(folder.id))
                    }) {
                        FolderThumbnailViewWithCache(folder: folder)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

struct NoFolderView: View {
    var body: some View {
        GalleryPlaceholderView(
            systemImage: "folder",
            title: String(localized: "No Folders"),
            message: String(localized: "Folders will appear here after the library syncs.")
        )
    }
}

struct NoResultsView: View {
    var body: some View {
        GalleryPlaceholderView(
            systemImage: "magnifyingglass",
            title: String(localized: "Nothing Found"),
            message: String(localized: "Try a different name, tag, extension, or fewer search terms.")
        )
    }
}

struct GalleryPlaceholderView: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack {
            Spacer(minLength: 20)

            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 52, weight: .light))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 20)
        }
        .frame(minHeight: 220)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}
