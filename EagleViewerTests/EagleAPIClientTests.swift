//
//  EagleAPIClientTests.swift
//  EagleViewerTests
//
//  Created on 2026/05/07.
//

import Foundation
import XCTest
@testable import EagleViewer

final class EagleAPIClientTests: XCTestCase {
    func test_urlRequest_withToken_shouldAppendTokenQueryParameter() throws {
        // Arrange
        let configuration = EagleAPIConfiguration(
            baseURL: URL(string: "http://192.168.1.20:41595/api/v2")!,
            token: "secret-token"
        )
        let client = EagleAPIClient(configuration: configuration, transport: MockEagleAPITransport())

        // Act
        let request = try client.urlRequest(path: "library/info", method: "GET")

        // Assert
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.20:41595/api/v2/library/info?token=secret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_appInfo_withSuccessResponse_shouldDecodePayload() async throws {
        // Arrange
        let data = Data("""
        {
          "status": "success",
          "data": {
            "version": "4.0.0",
            "prereleaseVersion": null,
            "buildVersion": "21",
            "platform": "darwin"
          }
        }
        """.utf8)
        let transport = MockEagleAPITransport(data: data)
        let client = EagleAPIClient(configuration: .localhost(), transport: transport)

        // Act
        let info = try await client.appInfo()

        // Assert
        XCTAssertEqual(info.version, "4.0.0")
        XCTAssertEqual(info.buildVersion, "21")
        XCTAssertEqual(info.platform, "darwin")
    }

    func test_items_withPaginatedResponse_shouldDecodePage() async throws {
        // Arrange
        let data = Data("""
        {
          "status": "success",
          "data": {
            "data": [
              {
                "id": "ITEM-A",
                "name": "Poster",
                "ext": "png",
                "modificationTime": 100
              }
            ],
            "total": 2,
            "offset": 0,
            "limit": 1
          }
        }
        """.utf8)
        let transport = MockEagleAPITransport(data: data)
        let client = EagleAPIClient(configuration: .localhost(), transport: transport)

        // Act
        let page = try await client.items(EagleItemGetRequest(offset: 0, limit: 1))

        // Assert
        XCTAssertEqual(page.data.first?.id, "ITEM-A")
        XCTAssertEqual(page.total, 2)
        XCTAssertTrue(page.hasNextPage)
    }

    func test_folders_withPaginatedResponse_shouldDecodeFolderPage() async throws {
        // Arrange
        let data = Data("""
        {
          "status": "success",
          "data": {
            "data": [
              {
                "id": "FOLDER-A",
                "name": "Design References",
                "children": [],
                "modificationTime": 100
              }
            ],
            "total": 1,
            "offset": 0,
            "limit": 50
          }
        }
        """.utf8)
        let transport = MockEagleAPITransport(data: data)
        let client = EagleAPIClient(configuration: .localhost(), transport: transport)

        // Act
        let page = try await client.folders(EagleFolderGetRequest(offset: 0, limit: 50))

        // Assert
        XCTAssertEqual(page.data.first?.id, "FOLDER-A")
        XCTAssertEqual(page.data.first?.name, "Design References")
        XCTAssertFalse(page.hasNextPage)
    }

    func test_appInfo_withErrorResponse_shouldThrowAPIStatusMessage() async throws {
        // Arrange
        let data = Data("""
        {
          "status": "error",
          "message": "Token rejected"
        }
        """.utf8)
        let transport = MockEagleAPITransport(data: data)
        let client = EagleAPIClient(configuration: .localhost(), transport: transport)

        // Act & Assert
        do {
            _ = try await client.appInfo()
            XCTFail("Expected EagleAPIError.apiStatus")
        } catch EagleAPIError.apiStatus(let message) {
            XCTAssertEqual(message, "Token rejected")
        }
    }
}

private struct MockEagleAPITransport: EagleAPITransport {
    var data: Data
    var statusCode: Int

    init(data: Data = Data(#"{"status":"success","data":{}}"#.utf8), statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        return (data, response)
    }
}
