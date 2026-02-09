//
//  Tokenizer.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation
import NaturalLanguage

/**
 NLP based tokenizer to count words, sentences, etc.
 */
enum Tokenizer {
    static func count(text: String, unit: NLTokenUnit) -> Int {
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = text

        let tokens = tokenizer.tokens(for: text.startIndex..<text.endIndex)
        return tokens.count
    }
}
