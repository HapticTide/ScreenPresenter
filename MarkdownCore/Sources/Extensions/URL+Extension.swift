//
//  URL+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension URL {
    static var standardDirectories: [String: String] {
        [
            "home": homeDirectory,
            "documents": documentsDirectory,
            "library": libraryDirectory,
            "caches": cachesDirectory,
            "temporary": temporaryDirectory,
        ].mapValues {
            $0.path(percentEncoded: false)
        }
    }
}
