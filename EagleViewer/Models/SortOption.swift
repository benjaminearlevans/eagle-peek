//
//  SortOption.swift
//  EagleViewer
//
//  Created on 2025/08/25
//

enum GlobalSortType: String, CaseIterable, Codable, Hashable {
    case dateAdded = "dateAdded"
    case title = "title"
    case rating = "rating"
    
    var displayName: String {
        switch self {
        case .dateAdded:
            return String(localized: "Date Added")
        case .title:
            return String(localized: "Title")
        case .rating:
            return String(localized: "Rating")
        }
    }
}

struct GlobalSortOption: Codable, Equatable, Hashable {
    let type: GlobalSortType
    let ascending: Bool

    static let defaultValue: GlobalSortOption = .init(type: .dateAdded, ascending: true)
}

enum FolderItemSortType: String, CaseIterable, Codable, Hashable {
    case global = "global"
    case manual = "manual"
    case dateAdded = "dateAdded"
    case title = "title"
    case rating = "rating"
    
    var displayName: String {
        switch self {
        case .global:
            return String(localized: "Global Settings")
        case .manual:
            return String(localized: "Manual")
        case .dateAdded:
            return String(localized: "Date Added")
        case .title:
            return String(localized: "Title")
        case .rating:
            return String(localized: "Rating")
        }
    }
}

struct FolderItemSortOption: Codable, Equatable, Hashable {
    let type: FolderItemSortType
    let ascending: Bool

    static let defaultValue: FolderItemSortOption = .init(type: .global, ascending: true)
}

enum FolderSortType: String, CaseIterable, Codable, Hashable {
    case manual = "manual"
    case dateAdded = "dateAdded"
    case title = "title"
    
    var displayName: String {
        switch self {
        case .manual:
            return String(localized: "Manual")
        case .dateAdded:
            return String(localized: "Date Added")
        case .title:
            return String(localized: "Title")
        }
    }
}

struct FolderSortOption: Codable, Equatable, Hashable {
    let type: FolderSortType
    let ascending: Bool

    static let defaultValue: FolderSortOption = .init(type: .manual, ascending: true)
}
