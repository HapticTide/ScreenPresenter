//
//  WindowSettingsView.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import SettingsUI
import SwiftUI

@MainActor
struct WindowSettingsView: View {
    @State private var toolbarMode = AppPreferences.Window.toolbarMode
    @State private var tabbingMode = AppPreferences.Window.tabbingMode
    @State private var reduceTransparency = AppPreferences.Window.reduceTransparency

    var body: some View {
        SettingsForm {
            Section {
                Picker(Localized.Settings.toolbarMode, selection: $toolbarMode) {
                    Text(Localized.Settings.normalMode).tag(ToolbarMode.normal)
                    Text(Localized.Settings.compactMode).tag(ToolbarMode.compact)
                    Text(Localized.Settings.hiddenMode).tag(ToolbarMode.hidden)
                }
                .onChange(of: toolbarMode) {
                    AppPreferences.Window.toolbarMode = toolbarMode
                }
                .formMenuPicker()

                Picker(Localized.Settings.tabbingMode, selection: $tabbingMode) {
                    Text(Localized.Settings.automatic).tag(NSWindow.TabbingMode.automatic)
                    Text(Localized.Settings.preferred).tag(NSWindow.TabbingMode.preferred)
                    Text(Localized.Settings.disallowed).tag(NSWindow.TabbingMode.disallowed)
                }
                .onChange(of: tabbingMode) {
                    AppPreferences.Window.tabbingMode = tabbingMode
                }
                .formMenuPicker()
            }

            Section {
                Toggle(Localized.Settings.reduceTransparencyDescription, isOn: $reduceTransparency)
                    .onChange(of: reduceTransparency) {
                        AppPreferences.Window.reduceTransparency = reduceTransparency
                    }
                    .formLabel(Localized.Settings.reduceTransparencyLabel)
            }
        }
    }
}
