//
//  SyncIssueStore.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

protocol SyncIssueStore {
    func openIssues(for libraryId: Int64) async throws -> [SyncIssue]
    func issue(id: UUID) async throws -> SyncIssue?
    func save(_ issue: SyncIssue) async throws
    func markIssue(id: UUID, as state: SyncIssueResolutionState) async throws
}
