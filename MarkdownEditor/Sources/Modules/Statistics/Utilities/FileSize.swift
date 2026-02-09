//
//  FileSize.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

/**
 Utility to get human-readable file size.
 */
enum FileSize {
    static func readableSize(of fileURL: URL?) -> String? {
        guard let filePath = fileURL?.path else {
            return nil
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath) else {
            return nil
        }

        guard let fileSize = attributes[.size] as? Int64 else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
