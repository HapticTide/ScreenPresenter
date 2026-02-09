//
//  PreviewMessageHandler.swift
//  MarkdownPreview
//
//  Created by Sun on 2026/02/09.
//
//  JavaScript → Swift 消息处理
//

import WebKit

/// JavaScript 消息类型
enum PreviewMessageType: String {
    case ready
    case doubleClick
    case error
}

/// 预览消息处理器
final class PreviewMessageHandler: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    // MARK: - Properties
    
    private weak var delegate: PreviewMessageHandlerDelegate?
    
    // MARK: - Initialization
    
    init(delegate: PreviewMessageHandlerDelegate?) {
        self.delegate = delegate
        super.init()
    }
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            guard let body = message.body as? [String: Any],
                  let typeString = body["type"] as? String,
                  let type = PreviewMessageType(rawValue: typeString) else {
                return
            }
            
            switch type {
            case .ready:
                delegate?.previewDidFinishLoading()
            case .doubleClick:
                delegate?.previewDidReceiveDoubleClick()
            case .error:
                if let errorMessage = body["message"] as? String {
                    delegate?.previewDidReceiveError(errorMessage)
                }
            }
        }
    }
}

// MARK: - Delegate Protocol

@MainActor
protocol PreviewMessageHandlerDelegate: AnyObject {
    func previewDidFinishLoading()
    func previewDidReceiveDoubleClick()
    func previewDidReceiveError(_ message: String)
}
