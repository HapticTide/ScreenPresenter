//
//  WebRect+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation
import MarkdownCore

public extension WebRect {
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
