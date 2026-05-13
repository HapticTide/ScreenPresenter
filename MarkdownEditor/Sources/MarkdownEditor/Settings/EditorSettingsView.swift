//
//  EditorSettingsView.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import FontPicker
import MarkdownCore
import MarkdownKit
import SettingsUI
import SwiftUI

@MainActor
struct EditorSettingsView: View {
    @State private var lightTheme = AppPreferences.Editor.lightTheme
    @State private var darkTheme = AppPreferences.Editor.darkTheme
    @State private var showLineNumbers = AppPreferences.Editor.showLineNumbers
    @State private var showActiveLineIndicator = AppPreferences.Editor.showActiveLineIndicator
    @State private var showSelectionStatus = AppPreferences.Editor.showSelectionStatus
    @State private var invisiblesBehavior = AppPreferences.Editor.invisiblesBehavior
    @State private var typewriterMode = AppPreferences.Editor.typewriterMode
    @State private var focusMode = AppPreferences.Editor.focusMode
    @State private var lineWrapping = AppPreferences.Editor.lineWrapping
    @State private var lineHeight = AppPreferences.Editor.lineHeight
    @State private var tabKeyBehavior = AppPreferences.Editor.tabKeyBehavior
    @State private var indentUnit = AppPreferences.Editor.indentUnit

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Localized.Settings.font)
                FontPicker(configuration: fontPickerConfiguration, handlers: fontPickerHandlers)
            }

            Divider()

            SettingsForm {
                Section {
                    Picker(Localized.Settings.lightTheme, selection: $lightTheme) {
                        createThemePicker()
                    }
                    .onChange(of: lightTheme) { _ in
                        AppPreferences.Editor.lightTheme = lightTheme
                    }
                    .formMenuPicker()

                    Picker(Localized.Settings.darkTheme, selection: $darkTheme) {
                        createThemePicker()
                    }
                    .onChange(of: darkTheme) { _ in
                        AppPreferences.Editor.darkTheme = darkTheme
                    }
                    .formMenuPicker()
                }

                Section {
                    VStack(alignment: .leading) {
                        Toggle(isOn: $showLineNumbers) {
                            Text(Localized.Settings.lineNumbers)
                        }
                        .onChange(of: showLineNumbers) { _ in
                            AppPreferences.Editor.showLineNumbers = showLineNumbers
                        }

                        Toggle(isOn: $showActiveLineIndicator) {
                            Text(Localized.Settings.activeLineIndicator)
                        }
                        .onChange(of: showActiveLineIndicator) { _ in
                            AppPreferences.Editor.showActiveLineIndicator = showActiveLineIndicator
                        }

                        Toggle(isOn: $showSelectionStatus) {
                            Text(Localized.Settings.selectionStatus)
                        }
                        .onChange(of: showSelectionStatus) { _ in
                            AppPreferences.Editor.showSelectionStatus = showSelectionStatus
                        }
                    }
                    .formLabel(alignment: .top, Localized.Settings.displayOptions)

                    Picker(Localized.Settings.renderInvisibles, selection: $invisiblesBehavior) {
                        Text(Localized.Settings.never).tag(EditorInvisiblesBehavior.never)
                        Text(Localized.Settings.selection).tag(EditorInvisiblesBehavior.selection)
                        Text(Localized.Settings.trailing).tag(EditorInvisiblesBehavior.trailing)
                        Text(Localized.Settings.always).tag(EditorInvisiblesBehavior.always)
                    }
                    .onChange(of: invisiblesBehavior) { _ in
                        AppPreferences.Editor.invisiblesBehavior = invisiblesBehavior
                    }
                    .formMenuPicker()
                }

                Section {
                    VStack(alignment: .leading) {
                        Toggle(isOn: $typewriterMode) {
                            Text(Localized.Settings.typewriterModeTitle)
                        }
                        .onChange(of: typewriterMode) { _ in
                            AppPreferences.Editor.typewriterMode = typewriterMode
                        }

                        Toggle(isOn: $focusMode) {
                            Text(Localized.Settings.focusModeTitle)
                        }
                        .onChange(of: focusMode) { _ in
                            AppPreferences.Editor.focusMode = focusMode
                        }
                    }
                    .formLabel(alignment: .top, Localized.Settings.editBehavior)

                    Toggle(isOn: $lineWrapping) {
                        Text(Localized.Settings.lineWrappingDescription)
                    }
                    .onChange(of: lineWrapping) { _ in
                        AppPreferences.Editor.lineWrapping = lineWrapping
                    }
                    .formLabel(Localized.Settings.lineWrappingLabel)
                    .formBreathingInset()

                    Picker(Localized.Settings.lineHeight, selection: $lineHeight) {
                        Text(Localized.Settings.tightHeight).tag(LineHeight.tight)
                        Text(Localized.Settings.normalHeight).tag(LineHeight.normal)
                        Text(Localized.Settings.relaxedHeight).tag(LineHeight.relaxed)
                    }
                    .onChange(of: lineHeight) { _ in
                        AppPreferences.Editor.lineHeight = lineHeight
                    }
                    .formHorizontalRadio()
                    .formBreathingInset()
                }

                Section {
                    Picker(Localized.Settings.tabKeyBehavior, selection: $tabKeyBehavior) {
                        Text(Localized.Settings.insertsTab).tag(TabKeyBehavior.insertTab)
                        Text(Localized.Settings.insertsTwoSpaces).tag(TabKeyBehavior.insertTwoSpaces)
                        Text(Localized.Settings.insertsFourSpaces).tag(TabKeyBehavior.insertFourSpaces)
                        Text(Localized.Settings.indentsMore).tag(TabKeyBehavior.indentMore)
                    }
                    .onChange(of: tabKeyBehavior) { _ in
                        AppPreferences.Editor.tabKeyBehavior = tabKeyBehavior
                    }
                    .formMenuPicker()

                    Picker(Localized.Settings.indentUnit, selection: $indentUnit) {
                        Text(Localized.Settings.twoSpaces).tag(IndentUnit.twoSpaces)
                        Text(Localized.Settings.fourSpaces).tag(IndentUnit.fourSpaces)
                        Text(Localized.Settings.oneTab).tag(IndentUnit.oneTab)
                        Text(Localized.Settings.twoTabs).tag(IndentUnit.twoTabs)
                    }
                    .onChange(of: indentUnit) { _ in
                        AppPreferences.Editor.indentUnit = indentUnit
                    }
                    .formMenuPicker()
                }
            }
        }
    }
}

// MARK: - Private

private extension EditorSettingsView {
    var fontPickerConfiguration: FontPickerConfiguration {
        FontPickerConfiguration(
            modernStyle: AppDesign.modernStyle,
            selectedFontStyle: AppPreferences.Editor.fontStyle,
            selectedFontSize: AppPreferences.Editor.fontSize,
            selectButtonTitle: Localized.Settings.selectFont,
            moreFontsItemTitle: Localized.Settings.moreFonts,
            openPanelButtonTitle: Localized.Settings.openFontPanel,
            defaultFontName: Localized.Settings.systemDefault,
            monoFontName: Localized.Settings.systemMono,
            roundedFontName: Localized.Settings.systemRounded,
            serifFontName: Localized.Settings.systemSerif
        )
    }

    var fontPickerHandlers: FontPickerHandlers {
        FontPickerHandlers(
            fontStyleDidChange: { fontStyle in
                AppPreferences.Editor.fontStyle = fontStyle
            },
            fontSizeDidChange: { fontSize in
                AppPreferences.Editor.fontSize = fontSize
            }
        )
    }

    func createThemePicker() -> some View {
        ForEach(AppTheme.allCases, id: \.self) {
            Text($0.description).tag($0.editorTheme)
        }
    }
}
