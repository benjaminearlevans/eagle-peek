//
//  ImageDetailView.swift
//  EagleViewer
//
//  Created on 2025/08/20
//

import CoreGraphics
import Nuke
import SwiftUI

struct ImageDetailView: View {
    @State var selectedItem: Item
    let items: [Item]
    let dismiss: (Item) -> Void
    
    @State private var isNoUI = false
    @State private var swipeDisabled = false
    @State private var mainScrollId: String?
    @State private var thumbnailScrollId: String?
    @State private var isThumbnailScrolling = false

    @State private var scale: CGFloat = 1

    @State private var isInfoPresented = false
    @State private var isNoUIBeforeTextItem: Bool?
    @State private var toastMessage: String?
    
    private let prefetcher = ImagePrefetcher()
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    
    init(item: Item, items: [Item], dismiss: @escaping (Item) -> Void) {
        selectedItem = item
        self.items = items
        self.dismiss = dismiss
    }
    
    private func getImageURL(for item: Item) -> URL? {
        guard case .available(let url) = MediaFileResolver(libraryURL: libraryFolderManager.currentLibraryURL)
            .resolve(.original, for: item)
        else {
            return nil
        }

        return url
    }
    
    private func prefetchAdjacentImages(for item: Item) {
        guard let currentIndex = items.firstIndex(where: { $0.itemId == item.itemId }) else {
            return
        }
        
        var urlsToPrefetch: [URL] = []

        for offset in 1 ... 2 {
            let previousIndex = currentIndex - offset
            if previousIndex >= 0 {
                let previousItem = items[previousIndex]
                if !previousItem.isVideo,
                   !previousItem.isTextFile,
                   let previousURL = getImageURL(for: previousItem)
                {
                    urlsToPrefetch.append(previousURL)
                }
            }

            let nextIndex = currentIndex + offset
            if nextIndex < items.count {
                let nextItem = items[nextIndex]
                if !nextItem.isVideo,
                   !nextItem.isTextFile,
                   let nextURL = getImageURL(for: nextItem)
                {
                    urlsToPrefetch.append(nextURL)
                }
            }
        }
        
        if !urlsToPrefetch.isEmpty {
            let requests = urlsToPrefetch.map { ImageRequest(url: $0) }
            prefetcher.startPrefetching(with: requests)
        }
    }
    
    private func dragCloseGesture() -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                guard scale == 1 else { return }
                guard !selectedItem.isTextFile else { return }

                let w = abs(value.translation.width)
                let h = value.translation.height
                let predictedH = value.predictedEndTranslation.height
                if (h > 70 || predictedH > 140), w < max(44, h * 0.35) {
                    dismiss(selectedItem)
                }
            }
    }
    
    private func onScaleChanged(_ scale: CGFloat) {
        self.scale = scale
    }

    private func handleItemChange(oldItem: Item?, newItem: Item) {
        // Manage isNoUI state when switching to/from text files
        let oldIsText = oldItem?.isTextFile == true
        let newIsText = newItem.isTextFile

        if !oldIsText && newIsText {
            // Image/Video → Text: Save state and show UI
            isNoUIBeforeTextItem = isNoUI
            isNoUI = false
        } else if oldIsText && !newIsText {
            // Text → Image/Video: Restore saved state
            if let saved = isNoUIBeforeTextItem {
                isNoUI = saved
                isNoUIBeforeTextItem = nil
            }
        }
        // Text → Text: Do nothing (avoids flicker, preserves state)

        prefetchAdjacentImages(for: newItem)
        mainScrollId = newItem.itemId
        withAnimation(.easeInOut(duration: 0.2)) {
            thumbnailScrollId = newItem.itemId
        }
    }

    private var backgroundColor: Color {
        if selectedItem.isTextFile {
            return Color(.systemBackground)
        }

        return isNoUI ? .black : Color(.systemBackground)
    }

    private var selectedIndex: Int? {
        items.firstIndex(where: { $0.itemId == selectedItem.itemId })
    }

    private var navigationState: ViewerNavigationState {
        ViewerNavigationState(currentIndex: selectedIndex, totalCount: items.count)
    }

    private var viewerSubtitle: String {
        let position = (selectedIndex ?? 0) + 1
        return String(localized: "\(position) of \(items.count) - \(selectedItem.mediaKindLabel)")
    }

    private func selectItem(at index: Int) {
        guard items.indices.contains(index) else {
            return
        }

        selectedItem = items[index]
    }

    private func goToFirstItem() {
        selectItem(at: 0)
    }

    private func goToPreviousItem() {
        guard let index = navigationState.index(offsetBy: -1) else {
            return
        }

        selectItem(at: index)
    }

    private func goToNextItem() {
        guard let index = navigationState.index(offsetBy: 1) else {
            return
        }

        selectItem(at: index)
    }

    private func goToLastItem() {
        selectItem(at: items.count - 1)
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isNoUI.toggle()
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard toastMessage == message else {
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                toastMessage = nil
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let titleMaxWidth = max(0, geometry.size.width - 160)
            let titleButton = Button(action: {
                isInfoPresented.toggle()
            }) {
                VStack(spacing: 1) {
                    HStack(spacing: 8) {
                        Text(selectedItem.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Image(systemName: "info.circle")
                            .font(.body.weight(.regular))
                            .accessibilityHidden(true)
                    }

                    Text(viewerSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .frame(height: 44)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .regularGlassEffect(interactive: true)
            .accessibilityLabel("\(selectedItem.name), \(viewerSubtitle)")
            .accessibilityHint("Shows item information")

            ZStack {
                backgroundColor
                    .ignoresSafeArea()
                
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(items, id: \.itemId) { item in
                            let isItemSelected = (mainScrollId ?? selectedItem.itemId) == item.itemId

                            Group {
                                if item.isVideo {
                                    ItemVideoView(
                                        item: item,
                                        isSelected: isItemSelected,
                                        isNoUI: $isNoUI
                                    )
                                } else if item.isTextFile {
                                    ItemTextView(
                                        item: item,
                                        isSelected: isItemSelected,
                                        onDismiss: { dismiss(selectedItem) }
                                    )
                                } else {
                                    ItemImageView(
                                        item: item,
                                        isSelected: isItemSelected
                                    )
                                    .zoomable(
                                        isSelected: isItemSelected,
                                        isNoUI: $isNoUI,
                                        onScaleChanged: onScaleChanged
                                    )
                                }
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(item.itemId)
                        }
                    }
                    .scrollTargetLayout()
                }
                .ignoresSafeArea()
                .scrollDisabled(scale != 1)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $mainScrollId)
                .onAppear {
                    // Force scroll position to update after view appears
                    mainScrollId = selectedItem.itemId
                }
                .simultaneousGesture(dragCloseGesture())
                
                if !isNoUI {
                    VStack(spacing: 8) {
                        Spacer()
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 5) {
                                ForEach(Array(items.enumerated()), id: \.element.itemId) { index, item in
                                    let isSelected = !isThumbnailScrolling && item.itemId == selectedItem.itemId
                                    let isBeforeSelected = selectedIndex != nil && !isThumbnailScrolling && index < selectedIndex!
                                    let isAfterSelected = selectedIndex != nil && !isThumbnailScrolling && index > selectedIndex!

                                    Button {
                                        thumbnailScrollId = item.itemId
                                    } label: {
                                        ItemThumbnailView(item: item, textThumbnailStyle: .detailSlider)
                                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                            .aspectRatio(isSelected ? 1.0 : 0.72, contentMode: .fill)
                                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .stroke(
                                                        isSelected ? Color.accentColor : Color.white.opacity(0.28),
                                                        lineWidth: isSelected ? 2 : 1
                                                    )
                                            }
                                            .shadow(color: .black.opacity(isSelected ? 0.24 : 0), radius: 5, y: 2)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .offset(x: isBeforeSelected ? -10 : (isAfterSelected ? 10 : 0))
                                    .scaleEffect(isSelected ? 1.04 : 1)
                                    .accessibilityLabel("\(item.name), \(index + 1) of \(items.count)")
                                    .accessibilityValue(isSelected ? String(localized: "Selected") : item.mediaKindLabel)
                                    .accessibilityHint("Shows this item")
                                    .id(item.itemId)
                                    .animation(.easeInOut(duration: 0.2), value: selectedItem.itemId)
                                    .animation(.easeInOut(duration: 0.2), value: isThumbnailScrolling)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollIndicators(.hidden)
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $thumbnailScrollId, anchor: .center)
                        .safeAreaPadding(.horizontal, geometry.size.width / 2 - 22)
                        .frame(height: 44)
                        .frame(minWidth: geometry.size.width)
                        .clipShape(.rect)
                        .mask {
                            LinearGradient(gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.02),
                                .init(color: .black, location: 0.08),
                                .init(color: .black, location: 0.92),
                                .init(color: .clear, location: 0.98),
                            ]), startPoint: .leading, endPoint: .trailing)
                        }
                        .onAppear {
                            // Force scroll position to update after view appears
                            // (when initialized + UI enabled)
                            thumbnailScrollId = nil
                            DispatchQueue.main.async {
                                thumbnailScrollId = selectedItem.itemId
                                isThumbnailScrolling = false
                            }
                        }
                        .onChange(of: geometry.size) {
                            // Force scroll position to update after rotate screen
                            thumbnailScrollId = nil
                            DispatchQueue.main.async {
                                thumbnailScrollId = selectedItem.itemId
                                isThumbnailScrolling = false
                            }
                        }
                        .onScrollPhaseChange { lastPhase, newPhase in
                            // detect if thumbnails slider is scrolled by user
                            
                            if lastPhase == .idle && newPhase == .animating {
                                // when main scrolled: .idle -> .animating -> .idle
                                isThumbnailScrolling = false
                            } else {
                                // when thumbnail scrolled: .idle -> .interacting -> .decelerating -> .idle
                                isThumbnailScrolling = newPhase != .idle
                            }
                        }
                    }
                    .transition(.opacity)
                }

                if let toastMessage, !isNoUI {
                    VStack {
                        Spacer()
                        ViewerToastView(message: toastMessage)
                            .padding(.bottom, 104)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss(selectedItem)
                    }) {
                        Image(systemName: "chevron.down")
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel("Close viewer")
                }

                ToolbarItem(placement: .principal) {
                    ViewThatFits(in: .horizontal) {
                        titleButton
                        titleButton.frame(maxWidth: titleMaxWidth)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let imageURL = getImageURL(for: selectedItem) {
                        ShareLink(item: imageURL) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.primary)
                        }
                        .accessibilityLabel("Share item")
                    }

                    ViewerPowerToolsMenu(
                        item: selectedItem,
                        itemURL: getImageURL(for: selectedItem),
                        isChromeHidden: isNoUI,
                        navigationState: navigationState,
                        showInfo: {
                            isInfoPresented = true
                        },
                        toggleChrome: toggleChrome,
                        goToFirst: goToFirstItem,
                        goToPrevious: goToPreviousItem,
                        goToNext: goToNextItem,
                        goToLast: goToLastItem,
                        showCopiedMessage: showToast
                    )
                }
            }
            .toolbar(isNoUI ? .hidden : .visible, for: .navigationBar)
        }
        .sheet(isPresented: $isInfoPresented) {
            ItemInfoView(item: selectedItem)
                .presentationDetents([.medium, .large])
        }
        .navigationBarTitleDisplayMode(.inline)
        .statusBar(hidden: isNoUI)
        .onAppear {
            prefetchAdjacentImages(for: selectedItem)
        }
        .onDisappear {
            prefetcher.stopPrefetching()
        }
        
        // sync main scroll / thumbnails scroll / selectedItem
        .onChange(of: mainScrollId) {
            if let newId = mainScrollId, let item = items.first(where: { $0.itemId == newId }) {
                selectedItem = item
            }
        }
        .onChange(of: thumbnailScrollId) {
            if let newId = thumbnailScrollId, let item = items.first(where: { $0.itemId == newId }) {
                selectedItem = item
            }
        }
        .onChange(of: selectedItem) { oldItem, newItem in
            handleItemChange(oldItem: oldItem, newItem: newItem)
        }
    }
}
