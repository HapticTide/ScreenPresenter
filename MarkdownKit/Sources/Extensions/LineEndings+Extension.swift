//
//  LineEndings+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension LineEndings {
    var characters: String {
        switch self {
        case .crlf:
            "\r\n"
        case .cr:
            "\r"
        default:
            // LF is the preferred line endings on modern macOS
            "\n"
        }
    }
}
