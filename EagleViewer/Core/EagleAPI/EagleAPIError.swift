//
//  EagleAPIError.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

enum EagleAPIError: LocalizedError, Equatable {
    case invalidURL(String)
    case invalidResponse
    case httpStatus(Int)
    case apiStatus(String)
    case missingData

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Invalid Eagle API URL: \(path)"
        case .invalidResponse:
            return "Eagle API returned an invalid response."
        case .httpStatus(let statusCode):
            return "Eagle API request failed with HTTP \(statusCode)."
        case .apiStatus(let message):
            return message
        case .missingData:
            return "Eagle API response did not include data."
        }
    }
}
