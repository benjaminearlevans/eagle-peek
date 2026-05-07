//
//  CollectionView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB
import GRDBQuery
import SwiftUI

struct AllCollectionView: View {
    var body: some View {
        CollectionView<AllGalleryPageRequest>(title: String(localized: "All"), navigationDestination: .all)
    }
}

struct UncategorizedCollectionView: View {
    var body: some View {
        CollectionView<UncategorizedGalleryPageRequest>(title: String(localized: "Uncategorized"), navigationDestination: .uncategorized)
    }
}

struct RandomCollectionView: View {
    var body: some View {
        CollectionView<RandomGalleryPageRequest>(title: String(localized: "Random"), navigationDestination: .random)
    }
}

struct CollectionView<T: CollectionPageQueryable>: View where T.Value == GalleryPage, T.Context == DatabaseContext {
    let title: String
    let navigationDestination: NavigationDestination

    @State private var request: T

    @Environment(\.library) private var library
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var navigationManager: NavigationManager
    @EnvironmentObject private var searchManager: SearchManager

    init(title: String, navigationDestination: NavigationDestination) {
        self.title = title
        self.navigationDestination = navigationDestination
        _request = State(initialValue: T(
            libraryId: 0,
            sortOption: .defaultValue,
            searchText: "",
            limit: GalleryPageSize.initial
        ))
    }

    var body: some View {
        ScrollView {
            PagedItemListRequestView(
                request: $request,
                placeholderType: searchManager.debouncedSearchText.isEmpty ? .default : .search
            )
        }
        .ignoresSafeArea(edges: .horizontal)
        .searchDismissible()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: library.id, initial: true) {
            request.libraryId = library.id
            request.limit = GalleryPageSize.initial
        }
        .onChange(of: settingsManager.globalSortOption, initial: true) {
            request.sortOption = settingsManager.globalSortOption
            request.limit = GalleryPageSize.initial
        }
        .onAppear {
            searchManager.setSearchHandler(initialSearchText: request.searchText) { text in
                request.searchText = text
                request.limit = GalleryPageSize.initial
            }
        }
        .safeAreaPadding(.bottom, 52)
    }
}

protocol CollectionPageQueryable: GalleryPageQueryable {
    var libraryId: Int64 { get set }
    var sortOption: GlobalSortOption { get set }
    var searchText: String { get set }
    init(libraryId: Int64, sortOption: GlobalSortOption, searchText: String, limit: Int)
}

extension AllGalleryPageRequest: CollectionPageQueryable {}
extension UncategorizedGalleryPageRequest: CollectionPageQueryable {}
extension RandomGalleryPageRequest: CollectionPageQueryable {}
