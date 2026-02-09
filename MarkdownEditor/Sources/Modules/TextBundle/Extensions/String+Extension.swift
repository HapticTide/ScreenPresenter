//
//  String+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension String {
    /// https://textbundle.org/spec/
    var isTextBundle: Bool {
        self == "org.textbundle.package"
    }
}
