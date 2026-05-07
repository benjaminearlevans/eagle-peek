//
//  WaterfallGridView.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import SwiftUI

struct WaterfallGridView<Item: Identifiable, Content: View>: View {
    private struct Column {
        var items: [Item] = []
        var heightScore: CGFloat = 0
    }

    let items: [Item]
    let isCollection: Bool
    let aspectRatio: (Item) -> CGFloat
    @ViewBuilder let content: (Item) -> Content

    @EnvironmentObject private var settingsManager: SettingsManager
    @Environment(\.isPortrait) private var isPortrait

    init(
        items: [Item],
        isCollection: Bool,
        aspectRatio: @escaping (Item) -> CGFloat,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.isCollection = isCollection
        self.aspectRatio = aspectRatio
        self.content = content
    }

    var body: some View {
        let columns = balancedColumns()

        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: spacing) {
                    ForEach(column) { item in
                        content(item)
                            .aspectRatio(clampedAspectRatio(for: item), contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, horizontalPadding)
    }

    private var spacing: CGFloat {
        if isCollection {
            switch settingsManager.layout {
            case .col3:
                return 10
            case .col4:
                return 8
            case .col6:
                return 6
            }
        }

        return 4
    }

    private var horizontalPadding: CGFloat {
        isCollection ? 20 : 4
    }

    private var columnCount: Int {
        settingsManager.layout.columnCount(isPortrait: isPortrait)
    }

    private func balancedColumns() -> [[Item]] {
        guard items.isEmpty == false else {
            return []
        }

        var columns = Array(repeating: Column(), count: max(1, columnCount))
        for item in items {
            let columnIndex = shortestColumnIndex(in: columns)
            columns[columnIndex].items.append(item)
            columns[columnIndex].heightScore += estimatedHeightScore(for: item)
        }

        return columns.map(\.items)
    }

    private func shortestColumnIndex(in columns: [Column]) -> Int {
        columns.indices.min { left, right in
            columns[left].heightScore < columns[right].heightScore
        } ?? 0
    }

    private func estimatedHeightScore(for item: Item) -> CGFloat {
        (1 / clampedAspectRatio(for: item)) + 0.02
    }

    private func clampedAspectRatio(for item: Item) -> CGFloat {
        min(max(aspectRatio(item), 0.48), 2.4)
    }
}
