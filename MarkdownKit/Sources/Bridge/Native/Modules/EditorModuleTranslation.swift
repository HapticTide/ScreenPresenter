//
//  EditorModuleTranslation.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation
import MarkdownCore
import NaturalLanguage
#if canImport(Translation)
    import Translation
#endif

public final class EditorModuleTranslation: NativeModuleTranslation {
    public init() {}

    public func translate(text: String, from: String?, to: String?) async -> String {
        #if canImport(Translation)
            guard #available(macOS 26.0, *) else {
                return TranslationResponse(error: "Unsupported OS Version").jsonEncoded
            }

            do {
                let from = from ?? NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "en-US"
                let session = TranslationSession(from: from, to: to)
                try? await session.prepareTranslation()
                let response = try await session.translate(text)
                return TranslationResponse(text: response.targetText).jsonEncoded
            } catch {
                return TranslationResponse(error: error.localizedDescription).jsonEncoded
            }
        #else
            return TranslationResponse(error: "Translation Unavailable").jsonEncoded
        #endif
    }
}

// MARK: - Private

private struct TranslationResponse: Encodable {
    let text: String?
    let error: String?

    init(text: String? = nil, error: String? = nil) {
        self.text = text
        self.error = error
    }
}

#if canImport(Translation)
    @available(macOS 26.0, *)
    private extension TranslationSession {
        convenience init(from: String, to: String?) {
            self.init(
                installedSource: Locale.Language(identifier: from),
                target: to.map { Locale.Language(identifier: $0) }
            )
        }
    }
#endif
