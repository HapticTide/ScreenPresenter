//
//  FontPickerConfiguration.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import CoreText

public struct FontPickerConfiguration {
    let modernStyle: Bool
    let selectedFontStyle: FontStyle
    let selectedFontSize: Double
    let selectButtonTitle: String
    let moreFontsItemTitle: String
    let openPanelButtonTitle: String
    let defaultFontName: String
    let monoFontName: String
    let roundedFontName: String
    let serifFontName: String

    public init(
        modernStyle: Bool,
        selectedFontStyle: FontStyle,
        selectedFontSize: Double,
        selectButtonTitle: String,
        moreFontsItemTitle: String,
        openPanelButtonTitle: String,
        defaultFontName: String,
        monoFontName: String,
        roundedFontName: String,
        serifFontName: String
    ) {
        self.modernStyle = modernStyle
        self.selectedFontStyle = selectedFontStyle
        self.selectedFontSize = selectedFontSize
        self.selectButtonTitle = selectButtonTitle
        self.moreFontsItemTitle = moreFontsItemTitle
        self.openPanelButtonTitle = openPanelButtonTitle
        self.defaultFontName = defaultFontName
        self.monoFontName = monoFontName
        self.roundedFontName = roundedFontName
        self.serifFontName = serifFontName
    }
}

extension FontPickerConfiguration {
    func localizedInfo(style: FontStyle, size: Double) -> String {
        let name = switch style {
        case .systemDefault:
            defaultFontName
        case .systemMono:
            monoFontName
        case .systemRounded:
            roundedFontName
        case .systemSerif:
            serifFontName
        case let .customFont(name):
            CTFontCopyDisplayName(CTFontCreateWithName(name as CFString, size, nil)) as String
        }

        return "\(name) - \(String(format: "%.1f", size))"
    }
}
