//
//  EagleAPIModels.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

struct EagleAppInfo: Decodable, Equatable {
    let version: String?
    let prereleaseVersion: String?
    let buildVersion: String?
    let platform: String?
}

struct EagleLibraryInfo: Decodable, Equatable {
    let name: String?
    let path: String?
    let modificationTime: Int64?
    let applicationVersion: String?
}

struct EaglePage<Element: Decodable & Equatable>: Decodable, Equatable {
    let data: [Element]
    let total: Int
    let offset: Int
    let limit: Int

    var hasNextPage: Bool {
        offset + data.count < total
    }
}

struct EagleItem: Decodable, Equatable {
    let id: String
    let name: String?
    let size: Int?
    let btime: Int64?
    let mtime: Int64?
    let ext: String?
    let isDeleted: Bool?
    let modificationTime: Int64?
    let height: Int?
    let width: Int?
    let lastModified: Int64?
    let noThumbnail: Bool?
    let star: Int?
    let duration: Double?
    let folders: [String]?
    let order: [String: String]?
    let tags: [String]?
    let annotation: String?
    let url: String?
}

struct EagleItemGetRequest: Encodable, Equatable {
    var offset: Int
    var limit: Int
    var fields: [String]?
    var ids: [String]?
    var folders: [String]?
    var tags: [String]?
    var ext: String?
    var isUntagged: Bool?
    var isUnfiled: Bool?

    init(
        offset: Int = 0,
        limit: Int = 50,
        fields: [String]? = nil,
        ids: [String]? = nil,
        folders: [String]? = nil,
        tags: [String]? = nil,
        ext: String? = nil,
        isUntagged: Bool? = nil,
        isUnfiled: Bool? = nil
    ) {
        self.offset = max(0, offset)
        self.limit = min(max(1, limit), 1_000)
        self.fields = fields
        self.ids = ids
        self.folders = folders
        self.tags = tags
        self.ext = ext
        self.isUntagged = isUntagged
        self.isUnfiled = isUnfiled
    }
}

struct EagleItemQueryRequest: Encodable, Equatable {
    var query: String
    var offset: Int
    var limit: Int

    init(query: String, offset: Int = 0, limit: Int = 50) {
        self.query = query
        self.offset = max(0, offset)
        self.limit = min(max(1, limit), 1_000)
    }
}

struct EagleItemUpdateRequest: Codable, Equatable {
    let id: String
    var name: String?
    var tags: [String]?
    var star: Int?
    var annotation: String?
    var url: String?
    var folders: [String]?

    init(
        id: String,
        name: String? = nil,
        tags: [String]? = nil,
        star: Int? = nil,
        annotation: String? = nil,
        url: String? = nil,
        folders: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.tags = tags
        self.star = star.map { min(max($0, 0), 5) }
        self.annotation = annotation
        self.url = url
        self.folders = folders
    }
}
