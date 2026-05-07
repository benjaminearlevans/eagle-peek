//
//  Layout.swift
//  EagleViewer
//
//  Created on 2025/08/27
//

import Foundation

enum ListLayout: String, CaseIterable {
    case col2 = "col2"
    case col3 = "col3"
    
    func columnCount(isPortrait: Bool) -> Int {
        switch self {
        case .col2:
            2
        case .col3:
            3
        }
    }
    
    static let defaultValue: ListLayout = .col2
}
