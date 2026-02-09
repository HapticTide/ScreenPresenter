//
//  TextCompletionState.swift
//
//  Created by Sun on 2026/2/6.
//

import Observation

@Observable
final class TextCompletionState {
    var items = [String]()
    var query = ""
    var selectedIndex = 0
}
