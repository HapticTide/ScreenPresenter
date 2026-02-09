//
//  View+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import SwiftUI

extension View {
    var measuredSize: CGSize {
        let layoutWrapper = NSHostingController(rootView: self)
        layoutWrapper.view.layoutSubtreeIfNeeded()
        return layoutWrapper.view.fittingSize
    }
}
