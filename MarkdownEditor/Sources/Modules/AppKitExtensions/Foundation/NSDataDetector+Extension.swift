//
//  NSDataDetector+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension NSDataDetector {
    static func extractURL(from string: String) -> String? {
        let range = NSRange(location: 0, length: string.utf16.count)
        let detector = try? Self(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.firstMatch(in: string, range: range)?.url?.absoluteString
    }
}
