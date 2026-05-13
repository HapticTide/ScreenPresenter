//
//  TextCompletionState.swift
//
//  Created by Sun on 2026/2/6.
//

import Combine

final class TextCompletionState: ObservableObject {
    @Published var items = [String]()
    @Published var query = ""
    @Published var selectedIndex = 0
}
