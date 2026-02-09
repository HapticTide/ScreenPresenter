//
//  TextTokenizeAnchor+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension TextTokenizeAnchor {
    var afterSpace: Bool {
        guard pos > 0 else {
            return false
        }

        return text[text.utf16.index(text.startIndex, offsetBy: pos - 1)] == " "
    }
}
