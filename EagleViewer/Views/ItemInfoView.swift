//
//  ItemInfoView.swift
//  EagleViewer
//
//  Created on 2025/09/22
//

import GRDB
import GRDBQuery
import SwiftUI

struct ItemInfoView: View {
    @Query<StoredItemRequest> private var item: StoredItem
    @Query<ItemFoldersRequest> private var folders: [Folder]

    @Environment(\.library) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.repositories) private var repositories
    @State private var annotationDraft = ""
    @State private var errorMessage: String?

    init(item: Item) {
        _item = Query(StoredItemRequest(id: item.id))
        _folders = Query(ItemFoldersRequest(id: item.id))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ItemInfoOverview(item: item)
                    ItemInfoRatingEditor(rating: item.star) { rating in
                        updateRating(rating)
                    }

                    ItemInfoFolders(folders: folders)

                    ItemInfoTagEditor(
                        tags: item.tags,
                        addTag: addTag,
                        removeTag: removeTag
                    )

                    ItemInfoAnnotationEditor(annotation: $annotationDraft) {
                        updateAnnotation()
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Info")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .onChange(of: item.annotation, initial: true) {
            annotationDraft = item.annotation
        }
    }

    private var editingService: ItemEditingService {
        ItemEditingService(
            dbWriter: repositories.dbWriter,
            apiClient: library.eagleAPIConfiguration.map { configuration in
                EagleAPIClient(configuration: configuration)
            }
        )
    }

    private func updateRating(_ rating: Int) {
        Task {
            await performEdit {
                try await editingService.setRating(itemId: item.id, rating: rating)
            }
        }
    }

    private func addTag(_ tag: String) {
        Task {
            await performEdit {
                try await editingService.replaceTags(itemId: item.id, tags: item.tags + [tag])
            }
        }
    }

    private func removeTag(_ tag: String) {
        Task {
            await performEdit {
                try await editingService.replaceTags(
                    itemId: item.id,
                    tags: item.tags.filter { $0 != tag }
                )
            }
        }
    }

    private func updateAnnotation() {
        Task {
            await performEdit {
                try await editingService.updateAnnotation(itemId: item.id, annotation: annotationDraft)
            }
        }
    }

    @MainActor
    private func performEdit(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ItemInfoOverview: View {
    let item: StoredItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: item.name)
                .bold()
            Text(verbatim: metadataText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func sizeText(_ sizeInBytes: Int) -> String {
        let kb = 1024.0
        let mb = kb * 1024.0
        let gb = mb * 1024.0

        let size = Double(sizeInBytes)

        if size >= gb {
            return String(format: "%.1fGB", size / gb)
        } else if size >= mb {
            return String(format: "%.1fMB", size / mb)
        } else if size >= kb {
            return String(format: "%.1fKB", size / kb)
        } else {
            return "\(sizeInBytes)B"
        }
    }

    private var metadataText: String {
        let extText = item.ext.uppercased()
        let size = sizeText(item.size)
        if item.isTextFile {
            return "\(extText) · \(size)"
        }
        return "\(extText) · \(item.width) × \(item.height) · \(size)"
    }
}

struct ItemInfoFolders: View {
    let folders: [Folder]

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var imageViewerManager: ImageViewerManager
    @EnvironmentObject private var navigationManager: NavigationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folders")
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)
            FlowLayout(alignment: .leading) {
                if !folders.isEmpty {
                    ForEach(folders, id: \.folderId) { folder in
                        Button(action: {
                            moveToFolder(folder)
                        }) {
                            Text(verbatim: folder.name)
                                .lineLimit(1)
                                .modifier(ItemInfoTag())
                        }
                    }
                } else {
                    Button(action: {
                        moveToUncategorized()
                    }) {
                        Text("Uncategorized")
                            .modifier(ItemInfoTag())
                    }
                }
            }
        }
    }

    private func moveToFolder(_ folder: Folder) {
        dismiss()
        imageViewerManager.hide()
        DispatchQueue.main.async {
            navigationManager.path = [.folder(folder.id)]
        }
    }

    private func moveToUncategorized() {
        dismiss()
        imageViewerManager.hide()
        DispatchQueue.main.async {
            navigationManager.path = [.uncategorized]
        }
    }
}

struct StoredItemRequest: ValueObservationQueryable {
    let id: Item.ID

    static var defaultValue: StoredItem {
        return StoredItem.empty
    }

    func fetch(_ db: Database) throws -> StoredItem {
        let item = try StoredItem
            .filter(Column("libraryId") == id.libraryId)
            .filter(Column("itemId") == id.itemId)
            .filter(Column("isDeleted") == false)
            .fetchOne(db)
        return item ?? StoredItem.empty
    }
}

struct ItemFoldersRequest: ValueObservationQueryable {
    let id: Item.ID

    static var defaultValue: [Folder] {
        return []
    }

    func fetch(_ db: Database) throws -> [Folder] {
        return try Folder
            .filter(Column("libraryId") == id.libraryId)
            .joining(required: Folder.folderItems.filter(Column("itemId") == id.itemId))
            .order(Column("manualOrder"))
            .fetchAll(db)
    }
}

struct ItemInfoTag: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .foregroundColor(.primary.opacity(0.6))
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(AppTheme.Colors.subtleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .stroke(AppTheme.Colors.separator)
            )
    }
}
