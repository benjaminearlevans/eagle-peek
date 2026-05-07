//
//  EagleAPIConfiguration.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

enum EagleAPIAuthentication: Equatable, Hashable {
    case none
    case queryToken
    case bearerToken
}

struct EagleAPIConfiguration: Equatable, Hashable {
    static let defaultPort = 41595
    static let defaultAPIPath = "/api/v2/"

    var baseURL: URL
    var token: String?
    var timeoutInterval: TimeInterval
    var authentication: EagleAPIAuthentication

    init(
        baseURL: URL,
        token: String? = nil,
        timeoutInterval: TimeInterval = 10,
        authentication: EagleAPIAuthentication = .queryToken
    ) {
        self.baseURL = baseURL
        self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.timeoutInterval = timeoutInterval
        self.authentication = authentication
    }

    static func localhost(token: String? = nil) -> EagleAPIConfiguration {
        EagleAPIConfiguration(baseURL: URL(string: "http://localhost:\(Self.defaultPort)\(Self.defaultAPIPath)")!, token: token)
    }

    static func url(fromUserInput input: String) -> URL? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.isEmpty == false else {
            return nil
        }

        if trimmedInput.contains("://") {
            return URL(string: trimmedInput)
        }

        return URL(string: "http://\(trimmedInput)")
    }

    var normalizedBaseURL: URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.withTrailingSlash
        }

        if components.scheme == "http", components.port == nil {
            components.port = Self.defaultPort
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = Self.defaultAPIPath
        }

        if components.path == "/api/v2" {
            components.path = Self.defaultAPIPath
        }

        if components.path.hasSuffix("/") == false {
            components.path += "/"
        }

        return components.url ?? baseURL.withTrailingSlash
    }
}

private extension URL {
    var withTrailingSlash: URL {
        let absoluteString = absoluteString
        if absoluteString.hasSuffix("/") {
            return self
        }

        return URL(string: absoluteString + "/") ?? self
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
