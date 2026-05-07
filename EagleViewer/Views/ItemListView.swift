//
//  ItemListView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB
import GRDBQuery
import SwiftUI

struct ItemListView: View {
    let items: [Item]
    let placeholderType: PlaceholderType
    let totalItemCount: Int?
    let loadNextPage: (() -> Void)?

    @EnvironmentObject var imageViewerManager: ImageViewerManager
    @EnvironmentObject private var searchManager: SearchManager
    @State private var selectedFilter: ItemMediaFilter = .all
    @State private var visibleItemCount = GalleryRenderWindow.defaultInitialLimit

    private let renderWindow = GalleryRenderWindow()

    init(
        items: [Item],
        placeholderType: PlaceholderType = .none,
        totalItemCount: Int? = nil,
        loadNextPage: (() -> Void)? = nil
    ) {
        self.items = items
        self.placeholderType = placeholderType
        self.totalItemCount = totalItemCount
        self.loadNextPage = loadNextPage
    }

    private func needShowType(item: Item) -> Bool {
        if item.isVideo {
            return true
        }

        if item.isTextFile {
            return true
        }

        if item.isAnimatedImage {
            return true
        }

        return false
    }

    var body: some View {
        if items.isEmpty && placeholderType != .none {
            switch placeholderType {
            case .search:
                NoResultsView()
            case .default:
                NoItemView()
            case .none:
                EmptyView()
            }
        } else {
            let availableFilters = ItemMediaFilter.availableFilters(for: items)
            let filteredItems = selectedFilter.items(from: items)
            let renderedItems = Array(filteredItems.prefix(visibleItemCount))
            let displayTotalCount = totalItemCount ?? filteredItems.count
            let hasUnloadedItems = filteredItems.count < displayTotalCount

            VStack(alignment: .leading, spacing: 12) {
                if availableFilters.count > 1 {
                    mediaFilterBar(availableFilters: availableFilters, visibleItemCount: filteredItems.count)
                }

                if filteredItems.isEmpty {
                    NoFilteredItemsView(filter: selectedFilter) {
                        selectedFilter = .all
                    }
                } else {
                    ScrollViewReader { proxy in
                        VStack(spacing: 12) {
                            AdaptiveGridView(isCollection: false) {
                                ForEach(renderedItems) { item in
                                    ItemThumbnailView(item: item)
                                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                        .contentShape(Rectangle())
                                        .if(needShowType(item: item)) { view in
                                            view.overlay(alignment: .topLeading) {
                                                Text(item.ext.uppercased())
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundColor(AppTheme.Colors.imageOverlayText.opacity(0.8))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 4)
                                                    .background(AppTheme.Colors.imageOverlayShadow)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                                    .padding(5)
                                                    .allowsHitTesting(false)
                                            }
                                        }
                                        .id(item.itemId)
                                        .accessibilityLabel(item.name)
                                        .accessibilityHint("Opens media viewer")
                                        .onTapGesture {
                                            searchManager.hideSearch()
                                            imageViewerManager.show(item: item, items: filteredItems, onDismiss: { selectedItem in
                                                ensureVisible(selectedItem, in: filteredItems)

                                                if item != selectedItem {
                                                    DispatchQueue.main.async {
                                                        proxy.scrollTo(selectedItem.itemId, anchor: .center)
                                                    }
                                                }
                                            })
                                        }
                                        .onAppear {
                                            if item == renderedItems.last {
                                                loadMoreIfNeeded(loadedCount: filteredItems.count, totalCount: displayTotalCount)
                                            }
                                        }
                                }
                            }

                            if renderedItems.count < filteredItems.count || hasUnloadedItems {
                                GalleryLoadMoreFooter(
                                    renderedCount: renderedItems.count,
                                    totalCount: displayTotalCount,
                                    loadMore: {
                                        loadMoreIfNeeded(loadedCount: filteredItems.count, totalCount: displayTotalCount)
                                    }
                                )
                            }
                        }
                        .onChange(of: searchManager.scrollToTopTrigger) {
                            if let firstItem = filteredItems.first {
                                proxy.scrollTo(firstItem.itemId, anchor: .top)
                            }
                        }
                    }
                }
            }
            .onChange(of: availableFilters) {
                if !availableFilters.contains(selectedFilter) {
                    selectedFilter = .all
                }
            }
            .onChange(of: selectedFilter) {
                resetRenderWindow(totalCount: filteredItems.count)
            }
            .onChange(of: items.count) { oldCount, newCount in
                if newCount < oldCount {
                    resetRenderWindow(totalCount: filteredItems.count)
                }
            }
        }
    }

    private func resetRenderWindow(totalCount: Int) {
        visibleItemCount = renderWindow.initialCount(total: totalCount)
    }

    private func loadMoreIfNeeded(loadedCount: Int, totalCount: Int) {
        if visibleItemCount < loadedCount {
            visibleItemCount = renderWindow.nextCount(current: visibleItemCount, total: loadedCount)
            return
        }

        guard loadedCount < totalCount else {
            return
        }

        loadNextPage?()
    }

    private func ensureVisible(_ item: Item, in items: [Item]) {
        guard let index = items.firstIndex(of: item) else {
            return
        }

        visibleItemCount = renderWindow.countIncluding(
            index: index,
            current: visibleItemCount,
            total: items.count
        )
    }

    private func mediaFilterBar(availableFilters: [ItemMediaFilter], visibleItemCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Media Type", selection: $selectedFilter) {
                ForEach(availableFilters) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Text(filterCountText(visibleItemCount: visibleItemCount))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private func filterCountText(visibleItemCount: Int) -> String {
        if selectedFilter == .all {
            return String(localized: "\(visibleItemCount) of \(totalItemCount ?? items.count) items")
        }

        return String(localized: "\(visibleItemCount) of \(items.count) items")
    }
}

struct ItemListRequestView<T: ValueObservationQueryable>: View where T.Value == [Item], T.Context == DatabaseContext {
    @Query<T> var items: [Item]
    let placeholderType: PlaceholderType

    init(request: Binding<T>, placeholderType: PlaceholderType = .none) {
        _items = Query(request, in: \.databaseContext)
        self.placeholderType = placeholderType
    }

    var body: some View {
        ItemListView(items: items, placeholderType: placeholderType)
    }
}

struct PagedItemListRequestView<T: GalleryPageQueryable>: View where T.Value == GalleryPage, T.Context == DatabaseContext {
    @Query<T> private var page: GalleryPage
    @Binding private var request: T
    let placeholderType: PlaceholderType

    init(request: Binding<T>, placeholderType: PlaceholderType = .none) {
        _request = request
        _page = Query(request, in: \.databaseContext)
        self.placeholderType = placeholderType
    }

    init(request: Query<T>.Wrapper, placeholderType: PlaceholderType = .none) {
        _request = request.request
        _page = Query(request.request, in: \.databaseContext)
        self.placeholderType = placeholderType
    }

    var body: some View {
        ItemListView(
            items: page.items,
            placeholderType: placeholderType,
            totalItemCount: page.totalCount,
            loadNextPage: loadNextPage
        )
    }

    private func loadNextPage() {
        guard request.limit < page.totalCount else {
            return
        }

        request.limit = min(page.totalCount, request.limit + GalleryPageSize.increment)
    }
}

struct NoItemView: View {
    var body: some View {
        GalleryPlaceholderView(
            systemImage: "photo.on.rectangle.angled",
            title: String(localized: "No Images"),
            message: String(localized: "This view is empty. Sync the library or try another folder.")
        )
    }
}

private struct NoFilteredItemsView: View {
    let filter: ItemMediaFilter
    let clearFilter: () -> Void

    var body: some View {
        GalleryPlaceholderView(
            systemImage: "line.3.horizontal.decrease.circle",
            title: String(localized: "No \(filter.title) Here"),
            message: String(localized: "Try another media type or show the full gallery."),
            actionTitle: String(localized: "Show All"),
            action: clearFilter
        )
    }
}
