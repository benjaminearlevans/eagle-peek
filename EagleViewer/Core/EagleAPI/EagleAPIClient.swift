//
//  EagleAPIClient.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

struct EagleAPIClient {
    private struct Envelope<Value: Decodable>: Decodable {
        let status: String
        let data: Value?
        let message: String?
    }

    private let configuration: EagleAPIConfiguration
    private let transport: EagleAPITransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configuration: EagleAPIConfiguration,
        transport: EagleAPITransport = URLSession.shared,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.transport = transport
        self.encoder = encoder
        self.decoder = decoder
    }

    func appInfo() async throws -> EagleAppInfo {
        try await get("app/info")
    }

    func libraryInfo() async throws -> EagleLibraryInfo {
        try await get("library/info")
    }

    func items(_ request: EagleItemGetRequest = EagleItemGetRequest()) async throws -> EaglePage<EagleItem> {
        try await post("item/get", body: request)
    }

    func queryItems(_ request: EagleItemQueryRequest) async throws -> EaglePage<EagleItem> {
        try await post("item/query", body: request)
    }

    func updateItem(_ request: EagleItemUpdateRequest) async throws {
        let _: EmptyPayload = try await post("item/update", body: request)
    }

    func urlRequest(path: String, method: String) throws -> URLRequest {
        try urlRequest(path: path, method: method, body: Optional<EmptyPayload>.none)
    }

    func urlRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) throws -> URLRequest {
        guard let url = url(path: path) else {
            throw EagleAPIError.invalidURL(path)
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func get<Value: Decodable>(_ path: String) async throws -> Value {
        let request = try urlRequest(path: path, method: "GET")
        return try await send(request)
    }

    private func post<Body: Encodable, Value: Decodable>(_ path: String, body: Body) async throws -> Value {
        let request = try urlRequest(path: path, method: "POST", body: body)
        return try await send(request)
    }

    private func send<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let (data, response) = try await transport.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EagleAPIError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw EagleAPIError.httpStatus(httpResponse.statusCode)
        }

        let envelope = try decoder.decode(Envelope<Value>.self, from: data)
        guard envelope.status == "success" else {
            throw EagleAPIError.apiStatus(envelope.message ?? "Eagle API request failed.")
        }

        guard let payload = envelope.data else {
            if Value.self == EmptyPayload.self, let empty = EmptyPayload() as? Value {
                return empty
            }

            throw EagleAPIError.missingData
        }

        return payload
    }

    private func url(path: String) -> URL? {
        let baseURL = configuration.normalizedBaseURL
        let url = baseURL.appending(path: path, directoryHint: .notDirectory)

        guard let token = configuration.token else {
            return url
        }

        return url.appending(queryItems: [URLQueryItem(name: "token", value: token)])
    }
}

struct EmptyPayload: Codable, Equatable {
    init() {}
}
