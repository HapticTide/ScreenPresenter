//
//  Encodable+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension Encodable {
    var jsonEncoded: String {
        (try? JSONEncoder().encode(self).toString()) ?? "{}"
    }
}
