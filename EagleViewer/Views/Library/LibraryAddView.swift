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
        case apiMediaFolderSelect
        case bridgeQRCodeScanner
    }

    private enum ConnectionMode: String, CaseIterable, Identifiable {
        case bridge
        case folder
        case eagleAPI

        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            switch self {
            case .bridge:
                return "Eagle Bridge"
            case .folder:
                return "Folder"
            case .eagleAPI:
                return "Eagle API"
            }
        }
    }

    private enum FormData {
        case folder(name: String, bookmarkData: Data, useLocalStorage: Bool)
        case eagleAPI(connection: APIConnectionData, libraryInfo: EagleLibraryInfo, mediaBookmarkData: Data)
    }

    private struct APIConnectionData: Equatable {
        let baseURL: URL
        let token: String?
    }

    @State private var connectionMode: ConnectionMode = .folder
    @State private var libraryName: String?
    @State private var libraryBookmarkData: Data?
    @State private var useLocalStorage = true
    @State private var apiBaseURLText = "http://localhost:41595/api/v2/"
    @State private var apiToken = ""
    @State private var apiLibraryInfo: EagleLibraryInfo?
    @State private var validatedAPIConnection: APIConnectionData?
    @State private var apiMediaLibraryName: String?
    @State private var apiMediaBookmarkData: Data?
    @State private var bridgePairingURLText = ""
    @State private var validationMessage: String?

    @State private var isLoading = false
    @State private var path = NavigationPath()

    @Environment(\.repositories) private var repositories
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                sourceSection
                setupSections
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
                case .apiMediaFolderSelect:
                    LibraryFolderSelectView { name, bookmarkData in
                        apiMediaLibraryName = name
                        apiMediaBookmarkData = bookmarkData
                        path = NavigationPath()
                    }
                case .bridgeQRCodeScanner:
                    BridgeQRCodeScannerView { value in
                        bridgePairingURLText = value
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
                                        validationMessage = creationFailureMessage(for: error, data: data)
                                    }
                                }
                                await MainActor.run {
                                    isLoading = false
                                }
                            }
                        }
                    }
                    .disabled(connectionMode == .bridge || validFormData == nil || isLoading)
                }
            }
            .onChange(of: apiBaseURLText) {
                resetAPISetupAfterInputChange()
            }
            .onChange(of: apiToken) {
                resetAPISetupAfterInputChange()
            }
            .onChange(of: connectionMode) {
                validationMessage = nil
            }
        }
    }

    private var sourceSection: some View {
        Section("Source") {
            Picker("Connection", selection: $connectionMode) {
                ForEach(ConnectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var setupSections: some View {
        switch connectionMode {
        case .bridge:
            bridgeSetupSections
        case .folder:
            folderSetupSections
        case .eagleAPI:
            apiSetupSections
        }
    }

    @ViewBuilder
    private var folderSetupSections: some View {
        Section("Library") {
            NavigationLink(value: Destination.folderSelect) {
                LabeledContent("Eagle Library Folder") {
                    Text(libraryName ?? "")
                }
            }
        }

        Section(
            header: Text("Options"),
            footer: Text("Recommended for slow external storage or network drives.")
        ) {
            Toggle("Download images locally", isOn: $useLocalStorage)
        }
    }

    private var apiSetupSections: some View {
        EagleAPISetupGuideView(
            baseURLText: $apiBaseURLText,
            token: $apiToken,
            libraryInfo: currentValidatedLibraryInfo,
            mediaLibraryName: apiMediaLibraryName,
            validationMessage: validationMessage,
            canValidate: apiConnectionData != nil && !isLoading,
            canSelectMedia: apiConnectionIsValidated && !isLoading,
            canCreate: apiFormData != nil,
            isLoading: isLoading,
            validateConnection: validateEagleAPIConnection,
            selectMediaFolder: {
                path.append(Destination.apiMediaFolderSelect)
            }
        )
    }

    private var bridgeSetupSections: some View {
        EagleBridgeSetupGuideView(
            pairingURLText: $bridgePairingURLText,
            validationMessage: validationMessage,
            isLoading: isLoading,
            scanQRCode: {
                path.append(Destination.bridgeQRCodeScanner)
            },
            connectBridge: connectEagleBridge
        )
    }

    private var validFormData: FormData? {
        switch connectionMode {
        case .bridge:
            return nil
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

    private var apiConnectionData: APIConnectionData? {
        let normalizedBaseURLText = apiBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = EagleAPIConfiguration.url(fromUserInput: normalizedBaseURLText),
              baseURL.scheme != nil,
              baseURL.host != nil else {
            return nil
        }

        let normalizedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration = EagleAPIConfiguration(baseURL: baseURL, token: normalizedToken)
        return APIConnectionData(
            baseURL: configuration.normalizedBaseURL,
            token: normalizedToken.isEmpty ? nil : normalizedToken
        )
    }

    private var apiConnectionIsValidated: Bool {
        guard let apiConnectionData else {
            return false
        }

        return apiConnectionData == validatedAPIConnection && apiLibraryInfo != nil
    }

    private var currentValidatedLibraryInfo: EagleLibraryInfo? {
        apiConnectionIsValidated ? apiLibraryInfo : nil
    }

    private var apiFormData: FormData? {
        guard let connection = apiConnectionData,
              apiConnectionIsValidated,
              let libraryInfo = apiLibraryInfo,
              let apiMediaBookmarkData
        else {
            return nil
        }

        return .eagleAPI(
            connection: connection,
            libraryInfo: libraryInfo,
            mediaBookmarkData: apiMediaBookmarkData
        )
    }

    private func validateEagleAPIConnection() {
        guard let data = apiConnectionData else {
            return
        }

        isLoading = true
        validationMessage = nil

        Task {
            do {
                let libraryInfo = try await validateEagleAPI(data)
                let displayName = libraryInfo.name ?? String(localized: "Eagle Library")
                await MainActor.run {
                    apiLibraryInfo = libraryInfo
                    validatedAPIConnection = data
                    validationMessage = String(localized: "Connected to \(displayName).")
                }
            } catch {
                Logger.app.error("Failed to validate Eagle API connection: \(error)")
                await MainActor.run {
                    clearAPIValidation()
                    validationMessage = validationFailureMessage(for: error, data: data)
                }
            }

            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func connectEagleBridge() {
        let trimmedPairingURL = bridgePairingURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pairingURL = URL(string: trimmedPairingURL) else {
            validationMessage = EagleBridgePairingError.invalidPairingURL.localizedDescription
            return
        }

        isLoading = true
        validationMessage = nil

        Task {
            do {
                let payload = try EagleBridgePairingPayload(pairingURL: pairingURL)
                let result = try await EagleBridgePairingClient().claim(payload)
                let client = EagleAPIClient(
                    configuration: EagleAPIConfiguration(
                        baseURL: result.apiBaseURL,
                        token: result.deviceToken,
                        timeoutInterval: 5,
                        authentication: .bearerToken
                    ),
                    retryPolicy: .none
                )
                _ = try await client.appInfo()
                let apiLibraryInfo = try await client.libraryInfo()
                let displayName = apiLibraryInfo.name ?? result.library.name ?? String(localized: "Eagle Library")
                let newLibrary = try await repositories.library.createEagleBridge(
                    name: displayName,
                    apiBaseURL: result.apiBaseURL,
                    deviceToken: result.deviceToken,
                    libraryPath: apiLibraryInfo.path ?? result.library.path
                )

                await MainActor.run {
                    settingsManager.setActiveLibrary(id: newLibrary.id)
                    dismiss()
                }
            } catch {
                Logger.app.error("Failed to pair Eagle Bridge: \(error)")
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
        case .eagleAPI(let connection, let libraryInfo, let mediaBookmarkData):
            let apiLibrary = try await repositories.library.createEagleAPI(
                name: libraryInfo.name ?? String(localized: "Eagle Library"),
                baseURL: connection.baseURL,
                token: connection.token,
                libraryPath: libraryInfo.path
            )
            newLibrary = try await repositories.library.updateEagleAPIMediaFolder(
                id: apiLibrary.id,
                bookmarkData: mediaBookmarkData
            )
        }

        await MainActor.run {
            // Set the newly created library as active
            settingsManager.setActiveLibrary(id: newLibrary.id)
            dismiss()
        }
    }

    private func validateEagleAPI(_ data: APIConnectionData) async throws -> EagleLibraryInfo {
        let client = EagleAPIClient(
            configuration: EagleAPIConfiguration(baseURL: data.baseURL, token: data.token, timeoutInterval: 3),
            retryPolicy: .none
        )
        _ = try await client.appInfo()
        return try await client.libraryInfo()
    }

    private func validationFailureMessage(for error: Error, data: APIConnectionData) -> String {
        if case EagleAPIError.apiStatus(let message) = error {
            return message
        }

        if isLocalNetworkPermissionDenied(error) {
            return String(localized: "Local Network permission is blocked. On iPhone, open Settings > Apps > Eagle Viewer > Local Network, enable it, then try again.")
        }

        let displayURL = EagleAPIConfiguration(baseURL: data.baseURL).normalizedBaseURL.absoluteString
        guard let urlError = error as? URLError else {
            return String(localized: "Could not validate Eagle Desktop at \(displayURL). \(error.localizedDescription)")
        }

        switch urlError.code {
        case .notConnectedToInternet:
            return String(localized: "The device is offline or Local Network access is blocked. Confirm Wi-Fi is connected, then enable Settings > Apps > Eagle Viewer > Local Network.")
        case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost:
            return String(localized: "Could not reach Eagle Desktop at \(displayURL). Confirm Eagle is open, Web API is enabled, the URL includes :41595, and both devices are on the same Wi-Fi.")
        default:
            return urlError.localizedDescription
        }
    }

    private func creationFailureMessage(for error: Error, data: FormData) -> String {
        switch data {
        case .folder:
            return error.localizedDescription
        case .eagleAPI(let connection, _, _):
            return validationFailureMessage(for: error, data: connection)
        }
    }

    private func isLocalNetworkPermissionDenied(_ error: Error) -> Bool {
        let errorDetails = String(describing: (error as NSError).userInfo)
        return errorDetails.localizedCaseInsensitiveContains("Local network prohibited")
    }

    private func clearAPIValidation() {
        apiLibraryInfo = nil
        validatedAPIConnection = nil
        apiMediaLibraryName = nil
        apiMediaBookmarkData = nil
    }

    private func resetAPISetupAfterInputChange() {
        clearAPIValidation()
        validationMessage = nil
    }
}
