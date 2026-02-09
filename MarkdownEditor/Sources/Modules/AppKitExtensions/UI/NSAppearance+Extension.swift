//
//  NSAppearance+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit

public extension NSAppearance {
    var isDarkMode: Bool {
        switch name {
        case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
            true
        default:
            false
        }
    }

    func resolvedName(isDarkMode: Bool) -> NSAppearance.Name {
        switch name {
        case .aqua, .darkAqua:
            // Aqua
            isDarkMode ? .darkAqua : .aqua
        case .vibrantLight, .vibrantDark:
            // Vibrant
            isDarkMode ? .vibrantDark : .vibrantLight
        case .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua:
            // High contrast
            isDarkMode ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
        case .accessibilityHighContrastVibrantLight, .accessibilityHighContrastVibrantDark:
            // High contrast vibrant
            isDarkMode ? .accessibilityHighContrastVibrantDark : .accessibilityHighContrastVibrantLight
        default:
            .aqua
        }
    }
}
