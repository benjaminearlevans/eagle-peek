//
//  ViewerToastView.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import SwiftUI

struct ViewerToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassBackground(in: Capsule())
            .accessibilityAddTraits(.isStaticText)
    }
}
