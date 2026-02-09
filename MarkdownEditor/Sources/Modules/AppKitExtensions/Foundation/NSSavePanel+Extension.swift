//
//  NSSavePanel+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import UniformTypeIdentifiers

public extension NSSavePanel {
    func enforceUniformType(_ type: UTType, completion: (() -> Void)? = nil) {
        let otherFileTypesWereAllowed = allowsOtherFileTypes
        allowsOtherFileTypes = false // Must turn this off temporarily to enforce the file type
        allowedContentTypes = [type]

        DispatchQueue.main.async {
            self.allowsOtherFileTypes = otherFileTypesWereAllowed
            completion?()
        }
    }
}
