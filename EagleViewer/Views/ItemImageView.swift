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

    private var imageURL: URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }

        return currentLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }

    private var aspectRatio: CGSize {
        CGSize(width: max(item.width, 1), height: max(item.height, 1))
    }

    var body: some View {
        Group {
            if let imageURL {
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
                placeholder(systemImage: "photo")
            }
        }
        .accessibilityLabel(item.name)
    }

    private func placeholder(systemImage: String?, showsProgress: Bool = false) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.18))
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
