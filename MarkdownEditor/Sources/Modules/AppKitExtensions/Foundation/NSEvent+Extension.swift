//
//  NSEvent+Extension.swift
//
//
//  Created by Sun on 2026/2/6.
//

import AppKit

public extension NSEvent {
    var deviceIndependentFlags: NSEvent.ModifierFlags {
        modifierFlags.intersection(.deviceIndependentFlagsMask)
    }
}

public extension NSEvent.ModifierFlags {
    private static let mapping: [String: NSEvent.ModifierFlags] = [
        "Shift": .shift,
        "Control": .control,
        "Option": .option,
        "Command": .command,
    ]

    init(stringValues: [String]) {
        var modifiers: NSEvent.ModifierFlags = []
        for stringValue in stringValues {
            if let modifier = Self.mapping[stringValue] {
                modifiers.insert(modifier)
            }
        }

        self = modifiers
    }
}

// https://gist.github.com/eegrok/949034
public extension UInt16 {
    static let kVK_ANSI_A: Self = 0x00
    static let kVK_ANSI_F: Self = 0x03
    static let kVK_ANSI_I: Self = 0x22
    static let kVK_Return: Self = 0x24
    static let kVK_Tab: Self = 0x30
    static let kVK_Space: Self = 0x31
    static let kVK_Delete: Self = 0x33
    static let kVK_Option: Self = 0x3a
    static let kVK_RightOption: Self = 0x3d
    static let kVK_F3: Self = 0x63
    static let kVK_LeftArrow: Self = 0x7b
    static let kVK_RightArrow: Self = 0x7c
    static let kVK_DownArrow: Self = 0x7d
    static let kVK_UpArrow: Self = 0x7e
}
