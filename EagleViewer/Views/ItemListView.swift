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

    @EnvironmentObject var imageViewerManager: ImageViewerManager
    @EnvironmentObject private var searchManager: SearchManager
    @State private var selectedFilter: ItemMediaFilter = .all

    init(items: [Item], placeholderType: PlaceholderType = .none) {
        self.items = items
        self.placeholderType = placeholderType
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
            let visibleItems = selectedFilter.items(from: items)

            VStack(alignment: .leading, spacing: 12) {
                if availableFilters.count > 1 {
                    mediaFilterBar(availableFilters: availableFilters, visibleItemCount: visibleItems.count)
                }

                if visibleItems.isEmpty {
                    NoFilteredItemsView(filter: selectedFilter) {
                        selectedFilter = .all
                    }
                } else {
                    ScrollViewReader { proxy in
                        AdaptiveGridView(isCollection: false) {
                            ForEach(visibleItems) { item in
                                ItemThumbnailView(item: item)
                                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipped()
                                    .contentShape(Rectangle())
                                    .if(needShowType(item: item)) { view in
                                        view.overlay(alignment: .topLeading) {
                                            Text(item.ext.uppercased())
                                                .font(.caption2.weight(.semibold))
                                                .foregroundColor(.white.opacity(0.8))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(.black.opacity(0.5))
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
                                        imageViewerManager.show(item: item, items: visibleItems, onDismiss: { selectedItem in
                                            if item != selectedItem {
                                                proxy.scrollTo(selectedItem.itemId, anchor: .center)
                                            }
                                        })
                                    }
                            }
                        }
                        .onChange(of: searchManager.scrollToTopTrigger) {
                            if let firstItem = visibleItems.first {
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
        }
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
            return String(localized: "\(items.count) items")
        }

        return String(localized: "\(visibleItemCount) of \(items.count) items")
    }
}

private enum ItemMediaFilter: String, CaseIterable, Identifiable {
    case all
    case photos
    case animated
    case videos
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return String(localized: "All")
        case .photos:
            return String(localized: "Photos")
        case .animated:
            return String(localized: "GIF")
        case .videos:
            return String(localized: "Videos")
        case .text:
            return String(localized: "Text")
        }
    }

    func items(from items: [Item]) -> [Item] {
        guard self != .all else {
            return items
        }

        return items.filter(contains)
    }

    static func availableFilters(for items: [Item]) -> [ItemMediaFilter] {
        var filters: [ItemMediaFilter] = [.all]
        filters += ItemMediaFilter.allCases.dropFirst().filter { filter in
            items.contains(where: filter.contains)
        }
        return filters
    }

    private func contains(item: Item) -> Bool {
        switch self {
        case .all:
            return true
        case .photos:
            return !item.isVideo
                && !item.isTextFile
                && !item.isAnimatedImage
        case .animated:
            return item.isAnimatedImage
        case .videos:
            return item.isVideo
        case .text:
            return item.isTextFile
        }
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
