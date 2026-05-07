//
//  LibraryAddView.swift
//  EagleViewer
//
//  Created on 2025/08/22
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct LibraryAddView: View {
    enum Destination: Hashable {
        case folderSelect
    }

    private enum ConnectionMode: String, CaseIterable, Identifiable {
        case folder
        case eagleAPI

        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            switch self {
            case .folder:
                return "Folder"
            case .eagleAPI:
                return "Eagle API"
            }
        }
    }

    private enum FormData {
        case folder(name: String, bookmarkData: Data, useLocalStorage: Bool)
        case eagleAPI(baseURL: URL, token: String?)
    }

    @State private var connectionMode: ConnectionMode = .folder
    @State private var libraryName: String?
    @State private var libraryBookmarkData: Data?
    @State private var useLocalStorage = true
    @State private var apiBaseURLText = "http://localhost:41595/api/v2/"
    @State private var apiToken = ""
    @State private var validationMessage: String?

    @State private var isLoading = false
    @State private var path = NavigationPath()

    @Environment(\.repositories) private var repositories
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Source") {
                    Picker("Connection", selection: $connectionMode) {
                        ForEach(ConnectionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch connectionMode {
                case .folder:
                    Section("Library") {
                        NavigationLink(value: Destination.folderSelect) {
                            LabeledContent("Eagle Library Folder") {
                                Text(libraryName ?? "")
                            }
                        }
                    }

                    Section(
                        header: Text("Options"),
                        footer: Text("Recommended for slow external storage or network drives."),
                        content: {
                            Toggle("Download images locally", isOn: $useLocalStorage)
                        }
                    )
                case .eagleAPI:
                    Section(
                        header: Text("Connection"),
                        footer: Text("Use localhost when testing in Simulator. Use your Mac IP address and Eagle API token when testing on a device.")
                    ) {
                        TextField("Base URL", text: $apiBaseURLText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("Token", text: $apiToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            validateEagleAPIConnection()
                        } label: {
                            Label("Validate Connection", systemImage: "checkmark.shield")
                        }
                        .disabled(apiFormData == nil || isLoading)
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
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .folderSelect:
                    LibraryFolderSelectView { name, bookmarkData in
                        self.libraryName = name
                        self.libraryBookmarkData = bookmarkData
                        // Pop back to root
                        path = NavigationPath()
                    }
                }
            }
            .navigationTitle("Add new library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let data = validFormData {
                            isLoading = true
                            Task {
                                do {
                                    try await createLibrary(from: data)
                                } catch {
                                    Logger.app.error("Failed to create library: \(error)")
                                    await MainActor.run {
                                        validationMessage = error.localizedDescription
                                    }
                                }
                                await MainActor.run {
                                    isLoading = false
                                }
                            }
                        }
                    }
                    .disabled(validFormData == nil || isLoading)
                }
            }
        }
    }

    private var validFormData: FormData? {
        switch connectionMode {
        case .folder:
            return folderFormData
        case .eagleAPI:
            return apiFormData
        }
    }

    private var folderFormData: FormData? {
        guard let libraryName, let libraryBookmarkData else {
            return nil
        }

        return .folder(name: libraryName, bookmarkData: libraryBookmarkData, useLocalStorage: useLocalStorage)
    }

    private var apiFormData: FormData? {
        let normalizedBaseURLText = apiBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: normalizedBaseURLText), baseURL.scheme != nil, baseURL.host != nil else {
            return nil
        }

        let normalizedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return .eagleAPI(baseURL: baseURL, token: normalizedToken.isEmpty ? nil : normalizedToken)
    }

    private func validateEagleAPIConnection() {
        guard let data = apiFormData else {
            return
        }

        isLoading = true
        validationMessage = nil

        Task {
            do {
                let libraryInfo = try await validateEagleAPI(data)
                let displayName = libraryInfo.name ?? String(localized: "Eagle Library")
                await MainActor.run {
                    validationMessage = String(localized: "Connected to \(displayName).")
                }
            } catch {
                Logger.app.error("Failed to validate Eagle API connection: \(error)")
                await MainActor.run {
                    validationMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func createLibrary(from data: FormData) async throws {
        let newLibrary: Library

        switch data {
        case .folder(let name, let bookmarkData, let useLocalStorage):
            newLibrary = try await repositories.library.create(
                name: name,
                bookmarkData: bookmarkData,
                useLocalStorage: useLocalStorage
            )
        case .eagleAPI(let baseURL, let token):
            let libraryInfo = try await validateEagleAPI(data)
            newLibrary = try await repositories.library.createEagleAPI(
                name: libraryInfo.name ?? String(localized: "Eagle Library"),
                baseURL: baseURL,
                token: token,
                libraryPath: libraryInfo.path
            )
        }

        await MainActor.run {
            // Set the newly created library as active
            settingsManager.setActiveLibrary(id: newLibrary.id)
            dismiss()
        }
    }

    private func validateEagleAPI(_ data: FormData) async throws -> EagleLibraryInfo {
        guard case .eagleAPI(let baseURL, let token) = data else {
            throw EagleAPIError.invalidURL("")
        }

        let client = EagleAPIClient(
            configuration: EagleAPIConfiguration(baseURL: baseURL, token: token)
        )
        _ = try await client.appInfo()
        return try await client.libraryInfo()
    }
}
