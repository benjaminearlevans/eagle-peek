//
//  SyncOperationQueue.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

protocol SyncOperationQueue {
    func enqueue(_ operation: SyncOperation) async throws
    func pendingOperations(for libraryId: Int64) async throws -> [SyncOperation]
    func update(_ operation: SyncOperation) async throws
    func removeOperation(id: UUID) async throws
}
