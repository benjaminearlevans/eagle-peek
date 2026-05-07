//
//  SyncIssueQuery.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import GRDB
import GRDBQuery

struct SyncIssuesRequest: ValueObservationQueryable {
    var libraryId: Int64?

    static var defaultValue: [SyncIssue] { [] }

    func fetch(_ db: Database) throws -> [SyncIssue] {
        guard let libraryId else {
            return []
        }

        return try SyncIssueRecord.fetchOpenIssues(db, libraryId: libraryId)
    }
}
