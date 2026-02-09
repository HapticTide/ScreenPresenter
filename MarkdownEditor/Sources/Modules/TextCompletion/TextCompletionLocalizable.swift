//
//  TextCompletionLocalizable.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public struct TextCompletionLocalizable: Sendable {
    let selectedHint: String

    public init(selectedHint: String) {
        self.selectedHint = selectedHint
    }
}
