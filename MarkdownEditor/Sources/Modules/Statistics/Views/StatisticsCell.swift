//
//  StatisticsCell.swift
//
//  Created by Sun on 2026/2/6.
//

import SwiftUI

struct StatisticsCell: View {
    let iconName: String
    let titleText: String
    let valueText: String

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: iconName)
                .frame(width: 28)
                .foregroundColor(.gray)
            Text(titleText)
                .fixedSize()
            Text(valueText)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement()
        .accessibilityLabel([titleText, valueText].joined(separator: " "))
        .frame(height: 32)
        Divider()
    }
}
