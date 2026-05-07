//
//  EagleBridgeSetupGuideView.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import SwiftUI

struct EagleBridgeSetupGuideView: View {
    @Binding var pairingURLText: String

    let validationMessage: String?
    let isLoading: Bool
    let scanQRCode: () -> Void
    let connectBridge: () -> Void

    var body: some View {
        Section(
            header: Text("Eagle Bridge"),
            footer: Text("Install and open the Eagle Peek Bridge plugin on your Mac. Your iPhone must be on the same network or connected through VPN for live sync.")
        ) {
            Label("One scan connects metadata, edits, and previews.", systemImage: "bolt.horizontal.circle")
                .foregroundStyle(AppTheme.Status.success)

            Button {
                scanQRCode()
            } label: {
                Label("Scan Bridge QR", systemImage: "qrcode.viewfinder")
            }
            .disabled(isLoading)

            TextField("Pairing link", text: $pairingURLText, axis: .vertical)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...4)

            Button {
                connectBridge()
            } label: {
                Label(isLoading ? "Connecting..." : "Connect Bridge", systemImage: "link")
            }
            .disabled(isLoading || pairingURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        Section("How It Works") {
            EagleBridgeCapabilityRow(
                title: "Metadata and edits",
                detail: "The bridge forwards requests to Eagle on your Mac.",
                systemImage: "arrow.left.arrow.right"
            )

            EagleBridgeCapabilityRow(
                title: "Previews and originals",
                detail: "The bridge reads media from the active Eagle library.",
                systemImage: "photo.on.rectangle"
            )

            EagleBridgeCapabilityRow(
                title: "Away from home",
                detail: "Cached items stay available. Edits queue until your Mac is reachable.",
                systemImage: "wifi.slash"
            )
        }

        if let validationMessage {
            Section {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct EagleBridgeCapabilityRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityElement(children: .combine)
    }
}
