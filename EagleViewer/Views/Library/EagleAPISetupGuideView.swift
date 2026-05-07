//
//  EagleAPISetupGuideView.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import SwiftUI

struct EagleAPISetupGuideView: View {
    @Binding var baseURLText: String
    @Binding var token: String

    let libraryInfo: EagleLibraryInfo?
    let mediaLibraryName: String?
    let validationMessage: String?
    let canValidate: Bool
    let canSelectMedia: Bool
    let canCreate: Bool
    let isLoading: Bool
    let validateConnection: () -> Void
    let selectMediaFolder: () -> Void

    var body: some View {
        Section("Setup Progress") {
            EagleAPISetupStepRow(
                number: 1,
                title: "Connect API",
                detail: "Metadata, tags, ratings, folders, and edits",
                status: libraryInfo == nil ? .current : .complete
            )

            EagleAPISetupStepRow(
                number: 2,
                title: "Add media folder",
                detail: "Image previews and local viewer cache",
                status: mediaFolderStatus
            )

            EagleAPISetupStepRow(
                number: 3,
                title: "Create library",
                detail: "First sync starts after setup completes",
                status: canCreate ? .current : .blocked
            )
        }

        Section(
            header: Text("Step 1: Connect Eagle API"),
            footer: Text("Use localhost in Simulator. On a device, use your Mac IP address with Eagle's API port, for example http://192.168.0.66:41595/api/v2/.")
        ) {
            TextField("Base URL", text: $baseURLText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Token", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                validateConnection()
            } label: {
                Label("Validate Connection", systemImage: "checkmark.shield")
            }
            .disabled(!canValidate)

            if let libraryInfo {
                LabeledContent("Connected library") {
                    Text(libraryInfo.name ?? String(localized: "Eagle Library"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }

        Section(
            header: Text("Step 2: Add Media Folder"),
            footer: Text("Eagle API does not provide image bytes. Select the same .library folder through Files, iCloud Drive, or a network share so previews can be cached.")
        ) {
            Button {
                selectMediaFolder()
            } label: {
                LabeledContent("Eagle .library folder") {
                    HStack(spacing: 6) {
                        Text(mediaLibraryName ?? String(localized: "Select"))
                            .foregroundColor(mediaLibraryName == nil ? .accentColor : .secondary)
                            .lineLimit(1)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(!canSelectMedia)

            Text("This folder is only used for media previews. Tags, ratings, annotations, and folder assignments still sync through the API.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("Step 3: Create and Sync") {
            Label(statusTitle, systemImage: canCreate ? "checkmark.circle.fill" : "clock")
                .foregroundStyle(canCreate ? AppTheme.Status.success : AppTheme.Status.neutral)
                .accessibilityElement(children: .combine)
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

    private var mediaFolderStatus: EagleAPISetupStepStatus {
        if mediaLibraryName != nil {
            return .complete
        }

        return libraryInfo == nil ? .blocked : .current
    }

    private var statusTitle: LocalizedStringKey {
        if canCreate {
            return "Ready to create library and start first sync"
        }

        if libraryInfo == nil {
            return "Connect Eagle API to continue"
        }

        return "Add the media folder to enable previews"
    }
}

private enum EagleAPISetupStepStatus {
    case complete
    case current
    case blocked
}

private struct EagleAPISetupStepRow: View {
    let number: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let status: EagleAPISetupStepStatus

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.18))
                    .frame(width: 30, height: 30)

                if status == .complete {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusColor)
                } else {
                    Text(number.formatted())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusColor)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch status {
        case .complete:
            return AppTheme.Status.success
        case .current:
            return .accentColor
        case .blocked:
            return AppTheme.Status.neutral
        }
    }
}
