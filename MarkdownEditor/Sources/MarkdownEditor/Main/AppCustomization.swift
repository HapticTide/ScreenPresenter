//
//  AppCustomization.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import Foundation
import MarkdownKit

/**
 Style sheet, script and config files to change the appearance and behavior of the app.

 Files are located at ~/Library/Containers/com.haptictide.screenpresenter.editor/Data/Documents/
 */
struct AppCustomization {
    enum FileType {
        case editorStyle
        case stylesDirectory
        case editorScript
        case scriptsDirectory
        case debugDirectory
        case pandoc
        case settings

        var tagName: String? {
            switch self {
            case .editorStyle, .stylesDirectory: "style"
            case .editorScript, .scriptsDirectory, .debugDirectory, .pandoc, .settings: nil
            }
        }

        var fileName: String {
            switch self {
            case .editorStyle: "editor.css"
            case .stylesDirectory: "styles"
            case .editorScript: "editor.js"
            case .scriptsDirectory: "scripts"
            case .debugDirectory: "debug"
            case .pandoc: "pandoc.yaml"
            case .settings: "settings.json"
            }
        }

        var isDirectory: Bool {
            switch self {
            case .stylesDirectory, .scriptsDirectory, .debugDirectory: true
            default: false
            }
        }
    }

    static let editorStyle = Self(fileType: .editorStyle)
    static let stylesDirectory = Self(fileType: .stylesDirectory)
    static let editorScript = Self(fileType: .editorScript)
    static let scriptsDirectory = Self(fileType: .scriptsDirectory)
    static let debugDirectory = Self(fileType: .debugDirectory)
    static let pandoc = Self(fileType: .pandoc)
    static let settings = Self(fileType: .settings)

    static func createFiles() {
        editorStyle.createFile()
        stylesDirectory.createFile()
        editorScript.createFile()
        scriptsDirectory.createFile()
        debugDirectory.createFile()
        pandoc.createFile("from: gfm\nstandalone: true\npdf-engine: context\n")
        settings.createFile(AppRuntimeConfig.defaultContents)
    }

    var fileURL: URL {
        URL.documentsDirectory.appending(
            path: fileType.fileName,
            directoryHint: fileType.isDirectory ? .isDirectory : .notDirectory
        ).resolvingSymbolicLink
    }

    var fileContents: String {
        createContents(url: fileURL) ?? ""
    }

    var directoryContents: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: fileURL,
            includingPropertiesForKeys: nil
        )) ?? []

        let sorted = files.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        return sorted.compactMap {
            guard ["css", "js"].contains($0.pathExtension.lowercased()) else {
                return nil
            }

            return createContents(url: $0.resolvingSymbolicLink)
        }
    }

    // MARK: - Private

    private let fileType: FileType

    @discardableResult
    private func createFile(_ contents: String = "") -> Bool {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }

        if fileType.isDirectory {
            try? FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        } else {
            try? contents.toData()?.write(to: fileURL)
        }

        return true
    }

    private func createContents(url: URL) -> String? {
        guard let contents = (try? Data(contentsOf: url))?.toString(), !contents.isEmpty else {
            return nil
        }

        // Create a label to better identify loaded contents
        let comment = " /* \(url.lastPathComponent) */"

        // JavaScript, create a closure to avoid declaration conflict
        if fileType == .editorScript || fileType == .scriptsDirectory {
            return "(() => {\(comment)\nmodule = typeof module === 'object' ? module : { exports: {} };\nexports = module.exports;\n\n\(contents)\n})();"
        }

        // Stylesheet, create a <style></style> element
        if let tagName = fileType.tagName {
            return "<\(tagName)>\(comment)\n\(contents)\n</\(tagName)>"
        }

        return contents
    }
}
