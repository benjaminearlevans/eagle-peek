//
//  GalleryLoadMoreFooter.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import SwiftUI

struct GalleryLoadMoreFooter: View {
    let renderedCount: Int
    let totalCount: Int
    let loadMore: () -> Void

    var body: some View {
        ProgressView(value: Double(renderedCount), total: Double(totalCount))
            .progressViewStyle(.linear)
            .padding(.horizontal, AppTheme.Layout.horizontalPagePadding)
            .padding(.vertical, 8)
            .accessibilityLabel("Loading more gallery items")
            .accessibilityValue("\(renderedCount) of \(totalCount) rendered")
            .onAppear(perform: loadMore)
    }
}
