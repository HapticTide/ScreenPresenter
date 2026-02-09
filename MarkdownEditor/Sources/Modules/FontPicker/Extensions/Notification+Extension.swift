//
//  Notification+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension Notification.Name {
    static let fontSizeChanged = Self("fontSizeChanged")
}

extension NotificationCenter {
    var fontSizePublisher: NotificationCenter.Publisher {
        publisher(for: .fontSizeChanged)
    }
}
