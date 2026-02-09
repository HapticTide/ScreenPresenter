//
//  AppRuntimeConfig.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import MarkdownCore
import MarkdownKit

/// Preferences for pro users, not directly visible in the Settings panel.
///
/// The underlying file is stored as "settings.json" in AppCustomization.
enum AppRuntimeConfig {
    struct Definition: Codable {
        enum VisualEffectType: String, Codable {
            case glass
            case blur
        }

        enum UpdateBehavior: String, Codable {
            case quiet
            case notify
            case never
        }

        struct HotKey: Codable {
            let key: String
            let modifiers: [String]
        }

        let autoCharacterPairs: Bool?
        let autoSaveWhenIdle: Bool?
        let closeAlwaysConfirmsChanges: Bool?
        let indentBehavior: EditorIndentBehavior?
        let writingToolsBehavior: String?
        let headerFontSizeDiffs: [Double]?
        let visibleWhitespaceCharacter: String?
        let visibleLineBreakCharacter: String?
        let searchNormalizers: [String: String]?
        let nativeSearchQuerySync: Bool?
        let customToolbarItems: [CustomToolbarItem]?
        let useClassicInterface: Bool?
        let visualEffectType: VisualEffectType?
        let updateBehavior: UpdateBehavior?
        let checksForUpdates: Bool? // [Deprecated] Kept for backward compatibility
        let defaultOpenDirectory: String?
        let defaultSaveDirectory: String?
        let disableCorsRestrictions: Bool?
        let mainWindowHotKey: HotKey?

        enum CodingKeys: String, CodingKey {
            case autoCharacterPairs = "editor.autoCharacterPairs"
            case autoSaveWhenIdle = "editor.autoSaveWhenIdle"
            case closeAlwaysConfirmsChanges = "editor.closeAlwaysConfirmsChanges"
            case indentBehavior = "editor.indentBehavior"
            case writingToolsBehavior = "editor.writingToolsBehavior"
            case headerFontSizeDiffs = "editor.headerFontSizeDiffs"
            case visibleWhitespaceCharacter = "editor.visibleWhitespaceCharacter"
            case visibleLineBreakCharacter = "editor.visibleLineBreakCharacter"
            case searchNormalizers = "editor.searchNormalizers"
            case nativeSearchQuerySync = "editor.nativeSearchQuerySync"
            case customToolbarItems = "editor.customToolbarItems"
            case useClassicInterface = "general.useClassicInterface"
            case visualEffectType = "general.visualEffectType"
            case updateBehavior = "general.updateBehavior"
            case checksForUpdates = "general.checksForUpdates"
            case defaultOpenDirectory = "general.defaultOpenDirectory"
            case defaultSaveDirectory = "general.defaultSaveDirectory"
            case disableCorsRestrictions = "general.disableCorsRestrictions"
            case mainWindowHotKey = "general.mainWindowHotKey"
        }
    }

    static let jsonLiteral: String = {
        guard let fileData, (try? JSONSerialization.jsonObject(with: fileData, options: [])) != nil else {
            Logger.assertFail("Invalid json file was found at: \(AppCustomization.settings.fileURL)")
            return nil
        }

        return fileData.toString()
    }() ?? "{}"

    static var jsonObject: [String: Any] {
        guard let data = fileData, let object = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }

        return (object as? [String: Any]) ?? [:]
    }

    static var autoCharacterPairs: Bool {
        // Enable auto character pairs by default
        currentDefinition.autoCharacterPairs ?? true
    }

    static var autoSaveWhenIdle: Bool {
        if closeAlwaysConfirmsChanges == true {
            // If changes require confirmation, they are not saved periodically
            return false
        }

        return currentDefinition.autoSaveWhenIdle ?? false
    }

    static var closeAlwaysConfirmsChanges: Bool? {
        // Changes are saved automatically by default
        currentDefinition.closeAlwaysConfirmsChanges
    }

    static var indentBehavior: EditorIndentBehavior {
        // No paragraph or line level indentation by default
        currentDefinition.indentBehavior ?? .never
    }

    @available(macOS 15.1, *)
    static var writingToolsBehavior: NSWritingToolsBehavior? {
        switch currentDefinition.writingToolsBehavior {
        case "none": NSWritingToolsBehavior.none
        case "complete": NSWritingToolsBehavior.complete
        case "limited": NSWritingToolsBehavior.limited
        default: nil
        }
    }

    static var headerFontSizeDiffs: [Double]? {
        // Rely on CoreEditor definitions by default
        currentDefinition.headerFontSizeDiffs
    }

    static var visibleWhitespaceCharacter: String? {
        currentDefinition.visibleWhitespaceCharacter
    }

    static var visibleLineBreakCharacter: String? {
        currentDefinition.visibleLineBreakCharacter
    }

    static var searchNormalizers: [String: String]? {
        currentDefinition.searchNormalizers
    }

    static var nativeSearchQuerySync: Bool {
        currentDefinition.nativeSearchQuerySync ?? false
    }

    static var customToolbarItems: [CustomToolbarItem] {
        currentDefinition.customToolbarItems ?? []
    }

    static var useClassicInterface: Bool {
        currentDefinition.useClassicInterface ?? false
    }

    static var visualEffectType: Definition.VisualEffectType {
        currentDefinition.visualEffectType ?? .glass
    }

    static var updateBehavior: Definition.UpdateBehavior {
        guard currentDefinition.checksForUpdates ?? true else {
            return .never
        }

        return currentDefinition.updateBehavior ?? .quiet
    }

    static var defaultOpenDirectory: String? {
        // Unspecified by default
        currentDefinition.defaultOpenDirectory
    }

    static var defaultSaveDirectory: String? {
        // Unspecified by default
        currentDefinition.defaultSaveDirectory
    }

    static var disableCorsRestrictions: Bool {
        // Enforce CORS restrictions by default
        currentDefinition.disableCorsRestrictions ?? false
    }

    static var mainWindowHotKey: Definition.HotKey? {
        // Shift-Command-Option-M by default
        currentDefinition.mainWindowHotKey
    }

    static var defaultContents: String {
        encode(definition: defaultDefinition)?.toString() ?? ""
    }
}

struct CustomToolbarItem: Codable {
    let title: String
    let icon: String
    let actionName: String?
    let menuName: String?

    var identifier: NSToolbarItem.Identifier {
        let components = [
            title,
            icon,
            actionName,
            menuName,
        ].compactMap(\.self).joined(separator: "-")

        let prefix = "com.haptictide.screenpresenter.custom"
        return NSToolbarItem.Identifier(rawValue: "\(prefix).\(components.sha256Hash)")
    }
}

// MARK: - Private

private extension AppRuntimeConfig {
    /**
     The raw JSON data of the settings.json file.
     */
    static let fileData = try? Data(contentsOf: AppCustomization.settings.fileURL)

    static let defaultDefinition = Definition(
        autoCharacterPairs: true,
        autoSaveWhenIdle: false,
        closeAlwaysConfirmsChanges: nil,
        indentBehavior: .never,
        writingToolsBehavior: nil, // [macOS 15] Complete mode still has lots of bugs
        headerFontSizeDiffs: nil,
        visibleWhitespaceCharacter: nil,
        visibleLineBreakCharacter: nil,
        searchNormalizers: nil,
        nativeSearchQuerySync: false,
        customToolbarItems: [],
        useClassicInterface: nil,
        visualEffectType: nil,
        updateBehavior: .quiet,
        checksForUpdates: nil,
        defaultOpenDirectory: nil,
        defaultSaveDirectory: nil,
        disableCorsRestrictions: nil,
        mainWindowHotKey: .init(key: "M", modifiers: ["Shift", "Command", "Option"])
    )

    /// 当前配置定义（如果文件不存在则使用默认值）
    static var currentDefinition: Definition {
        // 尝试从文件加载
        if
            let fileData,
            let definition = try? JSONDecoder().decode(Definition.self, from: fileData) {
            return definition
        }
        // 文件不存在或解析失败时返回基于默认内容解析的定义
        // 这样可以避免首次启动时崩溃
        if
            let defaultData = defaultContents.data(using: .utf8),
            let definition = try? JSONDecoder().decode(Definition.self, from: defaultData) {
            return definition
        }
        // 最后回退到代码中的默认值
        return Definition(
            autoCharacterPairs: true,
            autoSaveWhenIdle: false,
            closeAlwaysConfirmsChanges: nil,
            indentBehavior: .never,
            writingToolsBehavior: nil,
            headerFontSizeDiffs: nil,
            visibleWhitespaceCharacter: nil,
            visibleLineBreakCharacter: nil,
            searchNormalizers: nil,
            nativeSearchQuerySync: false,
            customToolbarItems: [],
            useClassicInterface: nil,
            visualEffectType: nil,
            updateBehavior: .quiet,
            checksForUpdates: nil,
            defaultOpenDirectory: nil,
            defaultSaveDirectory: nil,
            disableCorsRestrictions: nil,
            mainWindowHotKey: .init(key: "M", modifiers: ["Shift", "Command", "Option"])
        )
    }

    static func encode(definition: Definition) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData = try? encoder.encode(definition)
        Logger.assert(jsonData != nil, "Failed to encode object: \(definition)")

        return jsonData
    }
}
