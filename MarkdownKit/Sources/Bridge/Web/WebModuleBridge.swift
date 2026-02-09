//
//  WebModuleBridge.swift
//
//  Created by Sun on 2026/2/6.
//

import WebKit

/**
 Wrapper for all web bridges.
 */
@MainActor
public struct WebModuleBridge {
    public let config: WebBridgeConfig
    public let core: WebBridgeCore
    public let completion: WebBridgeCompletion
    public let history: WebBridgeHistory
    public let lineEndings: WebBridgeLineEndings
    public let textChecker: WebBridgeTextChecker
    public let selection: WebBridgeSelection
    public let format: WebBridgeFormat
    public let search: WebBridgeSearch
    public let toc: WebBridgeTableOfContents
    public let api: WebBridgeAPI
    public let writingTools: WebBridgeWritingTools
    public let foundationModels: WebBridgeFoundationModels

    public init(webView: WKWebView) {
        config = WebBridgeConfig(webView: webView)
        core = WebBridgeCore(webView: webView)
        completion = WebBridgeCompletion(webView: webView)
        history = WebBridgeHistory(webView: webView)
        lineEndings = WebBridgeLineEndings(webView: webView)
        textChecker = WebBridgeTextChecker(webView: webView)
        selection = WebBridgeSelection(webView: webView)
        format = WebBridgeFormat(webView: webView)
        search = WebBridgeSearch(webView: webView)
        toc = WebBridgeTableOfContents(webView: webView)
        api = WebBridgeAPI(webView: webView)
        writingTools = WebBridgeWritingTools(webView: webView)
        foundationModels = WebBridgeFoundationModels(webView: webView)
    }
}
