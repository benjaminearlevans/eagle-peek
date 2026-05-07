//
//  MediaFileResolver.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

enum MediaFileKind {
    case original
    case thumbnail
}

enum MediaFileResolution: Equatable {
    case available(URL)
    case missingLibraryURL
    case missingFile(URL)
}

struct MediaFileResolver {
    var libraryURL: URL?
    var fileExists: (URL) -> Bool = { url in
        FileManager.default.fileExists(atPath: url.path)
    }

    func resolve(_ kind: MediaFileKind, for item: some ItemPathProvider) -> MediaFileResolution {
        guard let libraryURL else {
            return .missingLibraryURL
        }

        let relativePath = switch kind {
        case .original:
            item.imagePath
        case .thumbnail:
            item.thumbnailPath
        }
        let url = libraryURL.appending(path: relativePath, directoryHint: .notDirectory)

        guard fileExists(url) else {
            return .missingFile(url)
        }

        return .available(url)
    }
}
