//
//  ProcessInfo+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit

public extension ProcessInfo {
    var semanticOSVer: String {
        let version = operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    var userAgent: String {
        "macOS/\(semanticOSVer)"
    }
}
