//
//  Color+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import SwiftUI

extension Color {
    static var accent: Self {
        Color(nsColor: .controlAccentColor)
    }

    static var label: Self {
        Color(nsColor: .labelColor)
    }
}
