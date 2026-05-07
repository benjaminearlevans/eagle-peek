//
//  Library+Environment.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import SwiftUI

private struct LibraryEnvironmentKey: EnvironmentKey {
    static let defaultValue: Library = Library(
        id: 0,
        name: "",
        bookmarkData: Data(),
        sortOrder: 0,
        lastImportedFolderMTime: 0,
        lastImportedItemMTime: 0,
        lastImportStatus: .none,
        lastImportError: nil,
        lastImportFailureCount: 0,
        lastImportFinishedAt: nil,
        lastSuccessfulImportAt: nil,
        useLocalStorage: false,
        sourceKind: .directFolder,
        apiBaseURL: nil,
        apiToken: nil,
        apiLibraryPath: nil
    )
}

extension EnvironmentValues {
    var library: Library {
        get { self[LibraryEnvironmentKey.self] }
        set { self[LibraryEnvironmentKey.self] = newValue }
    }
}
