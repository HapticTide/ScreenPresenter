//
//  WebBridgeSelection.swift
//
//  Generated using https://github.com/microsoft/ts-gyb
//
//  Don't modify this file manually, it's auto generated.
//
//  To make changes, edit template files under /CoreEditor/src/@codegen

import MarkdownCore
import WebKit

@MainActor
public final class WebBridgeSelection {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    public func selectWholeDocument(completion: ((Result<Void, WKWebView.InvokeError>) -> Void)? = nil) {
        webView?.invoke(path: "webModules.selection.selectWholeDocument", completion: completion)
    }

    public func getText() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView?.invoke(path: "webModules.selection.getText") {
                (result: Result<String, WKWebView.InvokeError>) in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func getRect(pos: Int) async throws -> WebRect? {
        struct Message: Encodable {
            let pos: Int
        }

        let message = Message(
            pos: pos
        )

        return try await withCheckedThrowingContinuation { continuation in
            webView?.invoke(path: "webModules.selection.getRect", message: message) {
                (result: Result<WebRect?, WKWebView.InvokeError>) in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func scrollToSelection(completion: ((Result<Void, WKWebView.InvokeError>) -> Void)? = nil) {
        webView?.invoke(path: "webModules.selection.scrollToSelection", completion: completion)
    }

    public func gotoLine(lineNumber: Int, completion: ((Result<Void, WKWebView.InvokeError>) -> Void)? = nil) {
        struct Message: Encodable {
            let lineNumber: Int
        }

        let message = Message(
            lineNumber: lineNumber
        )

        webView?.invoke(path: "webModules.selection.gotoLine", message: message, completion: completion)
    }

    public func refreshEditFocus(completion: ((Result<Void, WKWebView.InvokeError>) -> Void)? = nil) {
        webView?.invoke(path: "webModules.selection.refreshEditFocus", completion: completion)
    }

    public func navigateGoBack(completion: ((Result<Void, WKWebView.InvokeError>) -> Void)? = nil) {
        webView?.invoke(path: "webModules.selection.navigateGoBack", completion: completion)
    }
}
