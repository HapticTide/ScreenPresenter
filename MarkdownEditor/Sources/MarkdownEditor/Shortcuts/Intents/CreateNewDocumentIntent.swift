//
//  CreateNewDocumentIntent.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppIntents
import AppKit

struct CreateNewDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Create New Document"
    static let description =
        IntentDescription(
            "Creates a new document, with optional parameters to set the file name and the initial content."
        )
    static let openAppWhenRun = true
    static var parameterSummary: some ParameterSummary {
        Summary("New Document named \(\.$fileName) with \(\.$initialContent)")
    }

    @Parameter(title: "File Name")
    var fileName: String?

    @Parameter(title: "Initial Content", default: "")
    var initialContent: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        NSApp.appDelegate?.createNewFile(
            fileName: fileName,
            initialContent: initialContent,
            isIntent: true
        )

        return .result()
    }
}
