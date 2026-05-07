//
//  SyncOperation.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

enum SyncOperationKind: String, Codable, CaseIterable, Hashable {
    case updateItem
    case addItem
    case updateFolder
    case createFolder
    case updateTag
    case mergeTag
    case createSmartFolder
    case updateSmartFolder
}

enum SyncOperationState: String, Codable, CaseIterable, Hashable {
    case pending
    case applying
    case failed
    case conflicted
    case applied
}

struct SyncOperation: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var libraryId: Int64
    var itemId: String?
    var kind: SyncOperationKind
    var state: SyncOperationState
    var payload: Data
    var baselineModificationTime: Int64?
    var createdAt: Date
    var updatedAt: Date
    var failureMessage: String?

    init(
        id: UUID = UUID(),
        libraryId: Int64,
        itemId: String? = nil,
        kind: SyncOperationKind,
        state: SyncOperationState = .pending,
        payload: Data,
        baselineModificationTime: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        failureMessage: String? = nil
    ) {
        self.id = id
        self.libraryId = libraryId
        self.itemId = itemId
        self.kind = kind
        self.state = state
        self.payload = payload
        self.baselineModificationTime = baselineModificationTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.failureMessage = failureMessage
    }
}
