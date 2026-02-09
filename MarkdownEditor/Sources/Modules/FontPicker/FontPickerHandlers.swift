//
//  FontPickerHandlers.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public struct FontPickerHandlers {
    let fontStyleDidChange: (FontStyle) -> Void
    let fontSizeDidChange: (Double) -> Void

    public init(fontStyleDidChange: @escaping (FontStyle) -> Void, fontSizeDidChange: @escaping (Double) -> Void) {
        self.fontStyleDidChange = fontStyleDidChange
        self.fontSizeDidChange = fontSizeDidChange
    }
}
