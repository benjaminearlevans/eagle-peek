//
//  AppErrorView.swift
//  EagleViewer
//
//  Created on 2025/08/30
//

import SwiftUI

struct AppErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Status.critical)

            Text("An error occurred while starting the application.")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.appBackground)
    }
}
