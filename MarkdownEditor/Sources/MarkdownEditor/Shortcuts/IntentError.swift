//
//  IntentError.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import Foundation

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case missingDocument

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .missingDocument: "Missing active document to proceed."
        }
    }
}
