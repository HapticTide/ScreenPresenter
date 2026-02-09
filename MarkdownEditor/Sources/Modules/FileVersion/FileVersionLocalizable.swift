//
//  FileVersionLocalizable.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public struct FileVersionLocalizable: Sendable {
    let previous: String
    let next: String
    let cancel: String
    let revertTitle: String
    let modeTitles: [String]

    public init(
        previous: String,
        next: String,
        cancel: String,
        revertTitle: String,
        modeTitles: [String]
    ) {
        self.previous = previous
        self.next = next
        self.cancel = cancel
        self.revertTitle = revertTitle
        self.modeTitles = modeTitles
    }
}
