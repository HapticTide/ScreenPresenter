//
//  Bundle+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension Bundle {
    var shortVersionString: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var userAgent: String {
        "ScreenPresenter/\(shortVersionString ?? "0.0.0")"
    }
}
