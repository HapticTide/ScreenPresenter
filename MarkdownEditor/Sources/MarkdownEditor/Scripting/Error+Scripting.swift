//
//  Error+Scripting.swift
//  MarkdownEditor
//
//  Created by Stephen Kaplan on 4/4/25.
//

import Foundation

enum ScriptingError: Error, LocalizedError {
    case missingCommand
    case missingArgument(_ name: String)
    case editorNotFound(_ documentName: String)
    case jsEvaluationError(_ error: NSError)
    case invalidDestination(_ fileURL: URL, document: EditorDocument)
    case extensionMismatch(expectedExtension: String, outputType: String)

    var code: Int {
        switch self {
        case .missingCommand:
            NSCannotCreateScriptCommandError
        case .missingArgument:
            NSArgumentEvaluationScriptError
        case .editorNotFound:
            NSReceiverEvaluationScriptError
        case let .jsEvaluationError(_: error):
            error.code // WKError.javaScriptExceptionOccurred -- 4
        case .invalidDestination:
            NSArgumentsWrongScriptError
        case .extensionMismatch:
            NSArgumentsWrongScriptError
        }
    }

    func localizedDescription() -> String {
        switch self {
        case .missingCommand:
            return Localized.Scripting.missingCommandErrorMessage
        case let .missingArgument(_: name):
            return String(format: Localized.Scripting.missingArgumentErrorMessage, name)
        case let .editorNotFound(_: documentName):
            return String(format: Localized.Scripting.editorNotFoundErrorMessage, documentName)
        case let .jsEvaluationError(_: error):
            guard
                let lineNumber = error.userInfo["WKJavaScriptExceptionLineNumber"] as? Int,
                let columnNumber = error.userInfo["WKJavaScriptExceptionColumnNumber"] as? Int,
                let errorMessage = error.userInfo["WKJavaScriptExceptionMessage"] as? String else {
                return Localized.Scripting.unknownJSErrorMessage
            }

            return String(
                format: Localized.Scripting.jsEvaluationErrorMessage,
                lineNumber,
                columnNumber,
                errorMessage
            )
        case let .invalidDestination(fileURL, document):
            let validTypes = document.writableTypes(for: .saveOperation)
            let validExtensions = validTypes.compactMap {
                document.fileNameExtension(forType: $0, saveOperation: .saveOperation)
            }

            return String(
                format: Localized.Scripting.invalidDestinationErrorMessage,
                fileURL.pathExtension,
                validExtensions.joined(separator: ", ")
            )
        case let .extensionMismatch(expectedExtension, outputType):
            return String(
                format: Localized.Scripting.extensionMismatchErrorMessage,
                outputType,
                expectedExtension
            )
        }
    }

    func applyToCommand(_ command: NSScriptCommand) {
        command.scriptErrorNumber = code
        command.scriptErrorString = localizedDescription()
    }
}
