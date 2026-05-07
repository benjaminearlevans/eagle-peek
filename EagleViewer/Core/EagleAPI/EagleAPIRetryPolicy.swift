//
//  EagleAPIRetryPolicy.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

struct EagleAPIRetryPolicy: Equatable {
    let maxAttempts: Int
    let delayNanoseconds: UInt64

    init(maxAttempts: Int = 3, delayNanoseconds: UInt64 = 250_000_000) {
        self.maxAttempts = max(1, maxAttempts)
        self.delayNanoseconds = delayNanoseconds
    }

    static let `default` = EagleAPIRetryPolicy()
    static let none = EagleAPIRetryPolicy(maxAttempts: 1, delayNanoseconds: 0)

    func shouldRetry(error: Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let urlError = error as? URLError {
            return retryableURLCodes.contains(urlError.code)
        }

        guard let apiError = error as? EagleAPIError else {
            return false
        }

        switch apiError {
        case .httpStatus(let statusCode):
            return retryableHTTPStatusCodes.contains(statusCode)
        case .invalidURL, .invalidResponse, .apiStatus, .missingData:
            return false
        }
    }

    private var retryableURLCodes: Set<URLError.Code> {
        [
            .badServerResponse,
            .cannotConnectToHost,
            .cannotFindHost,
            .dataNotAllowed,
            .dnsLookupFailed,
            .internationalRoamingOff,
            .networkConnectionLost,
            .notConnectedToInternet,
            .secureConnectionFailed,
            .timedOut,
        ]
    }

    private var retryableHTTPStatusCodes: Set<Int> {
        [408, 425, 429, 500, 502, 503, 504]
    }
}
