//
//  AssistantSettingsView.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import MarkdownKit
import SettingsUI
import SwiftUI
import WebKit

@MainActor
struct AssistantSettingsView: View {
    @State private var insertFinalNewline = AppPreferences.Assistant.insertFinalNewline
    @State private var trimTrailingWhitespace = AppPreferences.Assistant.trimTrailingWhitespace
    @State private var wordsInDocument = AppPreferences.Assistant.wordsInDocument
    @State private var standardWords = AppPreferences.Assistant.standardWords
    @State private var guessedWords = AppPreferences.Assistant.guessedWords
    @State private var inlinePredictions = AppPreferences.Assistant.inlinePredictions
    @State private var suggestWhileTyping = AppPreferences.Assistant.suggestWhileTyping

    var body: some View {
        SettingsForm {
            Section {
                VStack(alignment: .leading) {
                    Toggle(isOn: $insertFinalNewline) {
                        Text(Localized.Settings.insertFinalNewline)
                    }
                    .onChange(of: insertFinalNewline) { _ in
                        AppPreferences.Assistant.insertFinalNewline = insertFinalNewline
                    }

                    Toggle(isOn: $trimTrailingWhitespace) {
                        Text(Localized.Settings.trimTrailingWhitespace)
                    }
                    .onChange(of: trimTrailingWhitespace) { _ in
                        AppPreferences.Assistant.trimTrailingWhitespace = trimTrailingWhitespace
                    }

                    Text(Localized.Settings.fileFormattingHint)
                        .formDescription()
                }
                .formLabel(alignment: .top, Localized.Settings.formatFiles)
            }

            Section {
                VStack(alignment: .leading) {
                    Toggle(isOn: $wordsInDocument) {
                        Text(Localized.Settings.wordsInDocument)
                    }
                    .onChange(of: wordsInDocument) { _ in
                        AppPreferences.Assistant.wordsInDocument = wordsInDocument
                    }

                    Toggle(isOn: $standardWords) {
                        Text(Localized.Settings.standardWords)
                    }
                    .onChange(of: standardWords) { _ in
                        AppPreferences.Assistant.standardWords = standardWords
                    }

                    Toggle(isOn: $guessedWords) {
                        Text(Localized.Settings.guessedWords)
                    }
                    .onChange(of: guessedWords) { _ in
                        AppPreferences.Assistant.guessedWords = guessedWords
                    }

                    Text(Localized.Settings.completionHint)
                        .formDescription()
                        .help("option-esc")
                }
                .formLabel(alignment: .top, Localized.Settings.completion)
            }

            Section {
                VStack(alignment: .leading) {
                    Toggle(isOn: $inlinePredictions) {
                        Text(Localized.Settings.inlinePredictions)
                    }
                    .onChange(of: inlinePredictions) { _ in
                        AppPreferences.Assistant.inlinePredictions = inlinePredictions
                    }

                    Toggle(isOn: $suggestWhileTyping) {
                        Text(Localized.Settings.suggestWhileTyping)
                    }
                    .onChange(of: suggestWhileTyping) { _ in
                        AppPreferences.Assistant.suggestWhileTyping = suggestWhileTyping
                    }
                }
                .formLabel(alignment: .top, Localized.Settings.autocomplete)
            }
        }
    }
}
