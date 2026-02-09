//
//  IntentProvider.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import Foundation
import AppIntents

struct IntentProvider: AppShortcutsProvider {
    
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNewDocumentIntent(),
            phrases: [
                "Create New Document in \(.applicationName)",
            ],
            shortTitle: "Create New Document",
            systemImageName: "plus.square"
        )
        AppShortcut(
            intent: EvaluateJavaScriptIntent(),
            phrases: [
                "Evaluate JavaScript in \(.applicationName)",
            ],
            shortTitle: "Evaluate JavaScript",
            systemImageName: "curlybraces.square"
        )
        AppShortcut(
            intent: GetFileContentIntent(),
            phrases: [
                "Get File Content in \(.applicationName)",
            ],
            shortTitle: "Get File Content",
            systemImageName: "doc.plaintext"
        )
        AppShortcut(
            intent: UpdateFileContentIntent(),
            phrases: [
                "Update File Content in \(.applicationName)",
            ],
            shortTitle: "Update File Content",
            systemImageName: "character.textbox"
        )
    }
}
