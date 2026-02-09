//
//  NSMenuItem+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit

public extension NSMenuItem {
    convenience init(title: String) {
        self.init(title: title, action: nil, keyEquivalent: "")
    }

    var copiedItem: NSMenuItem? {
        copy() as? NSMenuItem
    }

    func setOn(_ on: Bool) {
        state = on ? .on : .off
    }

    func toggle() {
        state.toggle()
    }

    /**
     Enable or disable an item, recursively if it contains a submenu.

     This is useful for disabling a menu while still allowing its items to be viewed.
     */
    func setEnabledRecursively(isEnabled: Bool) {
        if let submenu {
            submenu.autoenablesItems = false
            for item in submenu.items {
                item.setEnabledRecursively(isEnabled: isEnabled)
            }
        } else {
            self.isEnabled = isEnabled && target != nil && action != nil
        }
    }

    @MainActor
    func performAction() {
        guard let action else {
            return
        }

        NSApp.sendAction(action, to: target, from: self)
    }
}

extension NSControl.StateValue {
    mutating func toggle() {
        self = self == .on ? .off : .on
    }
}
