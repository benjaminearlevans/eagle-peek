//
//  SyncOperationEncoder.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

struct SyncOperationEncoder {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.encoder = encoder
        self.decoder = decoder
    }

    func encodeUpdateItem(_ request: EagleItemUpdateRequest) throws -> Data {
        try encoder.encode(request)
    }

    func decodeUpdateItem(from data: Data) throws -> EagleItemUpdateRequest {
        try decoder.decode(EagleItemUpdateRequest.self, from: data)
    }
}
