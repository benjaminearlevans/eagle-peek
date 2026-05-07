//
//  ItemThumbnailView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import NukeUI
import SwiftUI

struct ItemImageView: View {
    let item: Item
    let isSelected: Bool
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager

    private var mediaResolution: MediaFileResolution {
        MediaFileResolver(libraryURL: libraryFolderManager.currentLibraryURL)
            .resolve(.original, for: item)
    }

    private var aspectRatio: CGSize {
        CGSize(width: max(item.width, 1), height: max(item.height, 1))
    }

    var body: some View {
        Group {
            if case .available(let imageURL) = mediaResolution {
                if item.isAnimatedImage {
                    AnimatedImageView(
                        url: imageURL,
                        contentMode: .scaleAspectFit,
                        shouldAnimate: isSelected
                    )
                    .aspectRatio(aspectRatio, contentMode: .fit)
                } else {
                    LazyImage(url: imageURL) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(aspectRatio, contentMode: .fit)
                        } else if state.error != nil {
                            placeholder(systemImage: "exclamationmark.triangle")
                        } else {
                            placeholder(systemImage: nil, showsProgress: true)
                        }
                    }
                }
            } else {
                unavailablePlaceholder
            }
        }
        .accessibilityLabel(item.name)
    }

    private var unavailablePlaceholder: some View {
        placeholder(systemImage: "photo.badge.exclamationmark")
            .overlay(alignment: .bottom) {
                Text("Media unavailable")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 16)
                    .multilineTextAlignment(.center)
            }
    }

    private func placeholder(systemImage: String?, showsProgress: Bool = false) -> some View {
        Rectangle()
            .fill(AppTheme.Colors.placeholderFill)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if showsProgress {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
    }
}
