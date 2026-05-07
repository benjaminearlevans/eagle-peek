//
//  EagleBridgePairingClient.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation
import UIKit

struct EagleBridgePairingPayload: Equatable {
    let baseURL: URL
    let pairingCode: String

    init(pairingURL: URL) throws {
        guard pairingURL.scheme == "eaglepeek",
              pairingURL.host == "bridge-pair",
              let components = URLComponents(url: pairingURL, resolvingAgainstBaseURL: false),
              let baseValue = components.queryItems?.first(where: { $0.name == "baseURL" })?.value,
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let baseURL = URL(string: baseValue),
              !code.isEmpty
        else {
            throw EagleBridgePairingError.invalidPairingURL
        }

        self.baseURL = baseURL
        pairingCode = code
    }
}

struct EagleBridgePairingResult: Equatable {
    let apiBaseURL: URL
    let mediaBaseURL: URL
    let deviceToken: String
    let library: EagleBridgeLibraryInfo
}

struct EagleBridgeLibraryInfo: Codable, Equatable {
    let name: String?
    let path: String?
    let modificationTime: Int64?
}

enum EagleBridgePairingError: LocalizedError, Equatable {
    case invalidPairingURL
    case invalidResponse
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidPairingURL:
            return String(localized: "This is not a valid Eagle Peek pairing link.")
        case .invalidResponse:
            return String(localized: "Eagle Peek Bridge returned an invalid pairing response.")
        case .serverMessage(let message):
            return message
        }
    }
}

struct EagleBridgePairingClient {
    private struct ClaimRequest: Encodable {
        let pairingCode: String
        let deviceName: String
        let appVersion: String
    }

    private struct ClaimEnvelope: Decodable {
        let status: String
        let data: ClaimData?
        let message: String?
    }

    private struct ClaimData: Decodable {
        let apiBaseURL: URL
        let mediaBaseURL: URL
        let deviceToken: String
        let library: EagleBridgeLibraryInfo
    }

    var transport: EagleAPITransport = URLSession.shared
    var encoder = JSONEncoder()
    var decoder = JSONDecoder()

    func claim(_ payload: EagleBridgePairingPayload) async throws -> EagleBridgePairingResult {
        let claimURL = payload.baseURL.appending(path: "pair/claim", directoryHint: .notDirectory)
        var request = URLRequest(url: claimURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(ClaimRequest(
            pairingCode: payload.pairingCode,
            deviceName: UIDevice.current.name,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        ))

        let (data, response) = try await transport.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode
        else {
            throw EagleBridgePairingError.invalidResponse
        }

        let envelope = try decoder.decode(ClaimEnvelope.self, from: data)
        guard envelope.status == "success" else {
            throw EagleBridgePairingError.serverMessage(envelope.message ?? String(localized: "Eagle Peek Bridge pairing failed."))
        }

        guard let data = envelope.data else {
            throw EagleBridgePairingError.invalidResponse
        }

        return EagleBridgePairingResult(
            apiBaseURL: data.apiBaseURL,
            mediaBaseURL: data.mediaBaseURL,
            deviceToken: data.deviceToken,
            library: data.library
        )
    }
}
