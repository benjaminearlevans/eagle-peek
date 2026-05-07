//
//  GalleryDataSource.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import Foundation

protocol GalleryDataSource {
    func itemCount(for descriptor: GalleryDescriptor) async throws -> Int
    func page(for request: GalleryPageRequest) async throws -> GalleryPage
    func item(with id: Item.ID, in descriptor: GalleryDescriptor) async throws -> Item?
    func neighboringItems(around id: Item.ID, in descriptor: GalleryDescriptor, radius: Int) async throws -> [Item]
}
