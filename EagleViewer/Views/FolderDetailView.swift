import GRDB
import GRDBQuery
import SwiftUI

struct FolderDetailView: View {
    @Query<FolderRequest> private var folder: Folder?

    @EnvironmentObject private var navigationManager: NavigationManager

    init(id: Folder.ID) {
        _folder = Query(FolderRequest(libraryId: id.libraryId, folderId: id.folderId))
    }

    var body: some View {
        if let folder {
            FolderDetailInnerView(folder: folder)
        }
    }
}

struct FolderDetailInnerView: View {
    let folder: Folder
    @Query<FolderGalleryPageRequest> private var page: GalleryPage
    @Query<ChildFoldersRequest> private var childFolders: [Folder]

    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var searchManager: SearchManager
    @Environment(\.repositories) private var repositories

    init(folder: Folder) {
        self.folder = folder
        _page = Query(FolderGalleryPageRequest(folder: folder, globalSortOption: GlobalSortOption.defaultValue))
        _childFolders = Query(ChildFoldersRequest(folder: folder, folderSortOption: FolderSortOption.defaultValue))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !childFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !page.items.isEmpty {
                            Text("Subfolders")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                        }
                        FolderListView(folders: childFolders, placeholderType: .none, onSelected: onChildFolderSelected)
                    }
                }
                if !page.items.isEmpty || childFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !childFolders.isEmpty {
                            Text("Images")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                        }
                        PagedItemListRequestView(
                            request: $page,
                            placeholderType: childFolders.isEmpty ? (searchManager.debouncedSearchText.isEmpty ? .default : .search) : .none
                        )
                            .ignoresSafeArea(edges: .horizontal)
                    }
                }
            }
        }
        .searchDismissible()
        .safeAreaPadding(.bottom, 52)
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: folder, initial: true) {
            $page.folder.wrappedValue = folder
            $page.limit.wrappedValue = GalleryPageSize.initial
            $childFolders.folder.wrappedValue = folder
        }
        .onChange(of: settingsManager.globalSortOption, initial: true) {
            $page.globalSortOption.wrappedValue = settingsManager.globalSortOption
            $page.limit.wrappedValue = GalleryPageSize.initial
        }
        .onChange(of: settingsManager.folderSortOption, initial: true) {
            $childFolders.folderSortOption.wrappedValue = settingsManager.folderSortOption
        }
        .onAppear {
            searchManager.setSearchHandler(initialSearchText: $page.searchText.wrappedValue) { text in
                $page.searchText.wrappedValue = text
                $page.limit.wrappedValue = GalleryPageSize.initial
                $childFolders.searchText.wrappedValue = text
            }
        }
    }

    private func onChildFolderSelected(_ folder: Folder) {
        let searchText = searchManager.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            Task {
                try? await repositories.searchHistory.save(
                    SearchHistory(
                        libraryId: folder.libraryId,
                        searchHistoryType: .item,
                        searchText: searchText,
                        searchedAt: Date()
                    )
                )
            }
        }
    }
}

struct FolderRequest: ValueObservationQueryable {
    var libraryId: Int64
    var folderId: String

    static var defaultValue: Folder? { nil }

    func fetch(_ db: Database) throws -> Folder? {
        return try Folder
            .filter(Column("libraryId") == libraryId)
            .filter(Column("folderId") == folderId)
            .fetchOne(db)
    }
}

struct ChildFoldersRequest: ValueObservationQueryable {
    var folder: Folder
    var folderSortOption: FolderSortOption
    var searchText: String = ""

    static var defaultValue: [Folder] { [] }

    func fetch(_ db: Database) throws -> [Folder] {
        return try FolderQuery.childFolders(
            libraryId: folder.libraryId,
            parentId: folder.folderId,
            folderSortOption: folderSortOption,
            searchText: searchText
        ).fetchAll(db)
    }
}
