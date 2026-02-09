//
//  WebPoint+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation
import MarkdownCore

public extension WebPoint {
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}
