//
//  BackgroundTheming.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import AppKitExtensions

public protocol BackgroundTheming: NSView {}

public extension BackgroundTheming {
    @MainActor
    func setBackgroundColor(_ color: NSColor) {
        layerBackgroundColor = color
        needsDisplay = true

        enumerateDescendants { (button: NonBezelButton) in
            button.layerBackgroundColor = color
            button.needsDisplay = true
        }
    }
}
