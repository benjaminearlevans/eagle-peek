//
//  SyncIssue.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

enum SyncIssueSeverity: String, Codable, CaseIterable, Hashable {
    case info
    case warning
    case error
}

enum SyncIssueCategory: String, Codable, CaseIterable, Hashable {
    case connection
    case importMetadata
    case copyMedia
    case queuedEdit
    case conflict
    case storage
    case unknown
}

enum SyncIssueResolutionState: String, Codable, CaseIterable, Hashable {
    case open
    case retrying
    case ignored
    case resolved
}

struct SyncIssue: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var libraryId: Int64
    var itemId: String?
    var category: SyncIssueCategory
    var severity: SyncIssueSeverity
    var title: String
    var message: String
    var recoverySuggestion: String?
    var resolutionState: SyncIssueResolutionState
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        libraryId: Int64,
        itemId: String? = nil,
        category: SyncIssueCategory,
        severity: SyncIssueSeverity,
        title: String,
        message: String,
        recoverySuggestion: String? = nil,
        resolutionState: SyncIssueResolutionState = .open,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.libraryId = libraryId
        self.itemId = itemId
        self.category = category
        self.severity = severity
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.resolutionState = resolutionState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
