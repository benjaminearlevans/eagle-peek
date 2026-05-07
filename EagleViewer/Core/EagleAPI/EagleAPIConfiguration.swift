//
//  EagleAPIConfiguration.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

struct EagleAPIConfiguration: Equatable, Hashable {
    var baseURL: URL
    var token: String?
    var timeoutInterval: TimeInterval

    init(baseURL: URL, token: String? = nil, timeoutInterval: TimeInterval = 10) {
        self.baseURL = baseURL
        self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.timeoutInterval = timeoutInterval
    }

    static func localhost(token: String? = nil) -> EagleAPIConfiguration {
        EagleAPIConfiguration(baseURL: URL(string: "http://localhost:41595/api/v2/")!, token: token)
    }

    var normalizedBaseURL: URL {
        let absoluteString = baseURL.absoluteString
        if absoluteString.hasSuffix("/") {
            return baseURL
        }

        return URL(string: absoluteString + "/") ?? baseURL
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
