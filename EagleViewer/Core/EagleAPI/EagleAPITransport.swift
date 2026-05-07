//
//  EagleAPITransport.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

protocol EagleAPITransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: EagleAPITransport {}
