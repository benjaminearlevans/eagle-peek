//
//  MediaProvider.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

enum MediaVariant: String, Codable, Hashable {
    case thumbnail
    case preview
    case original
}

struct MediaRequest: Equatable, Hashable {
    let item: Item
    let variant: MediaVariant
}

protocol MediaProvider {
    func mediaURL(for request: MediaRequest) async throws -> URL?
    func isMediaAvailable(for request: MediaRequest) async -> Bool
}
