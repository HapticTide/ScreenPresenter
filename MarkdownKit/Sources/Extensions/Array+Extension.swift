//
//  Array+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension Array where Element: Hashable {
    /// Returns a new array by deduplicating elements and preserving the order.
    var deduplicated: [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
