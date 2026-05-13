//
//  NativeModules.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

/// Result wrapper crossing the WebKit script-message bridge.
public enum NativeMethodResult: @unchecked Sendable {
    case success(Any?)
    case failure(Error)
}

/// Native method that will be invoked by JavaScript.
public typealias NativeMethod = @Sendable (_ parameters: Data) async -> NativeMethodResult?

@MainActor
public protocol NativeBridge: AnyObject {
    static var name: String { get }
    var methods: [String: NativeMethod] { get }
}

/**
 Native module that implements JavaScript functions.

 Don't implement NativeModule directly with controllers, it will easily introduce retain cycles.
 */
@MainActor
public protocol NativeModule: AnyObject {
    var bridge: NativeBridge { get }
}

@MainActor
public struct NativeModules {
    private let bridges: [String: NativeBridge]

    public init(modules: [NativeModule]) {
        bridges = modules.reduce(into: [String: NativeBridge]()) { result, module in
            let bridge = module.bridge
            result[type(of: bridge).name] = bridge
        }
    }
}

// MARK: - Internal

extension NativeBridge {
    subscript(name: String) -> NativeMethod? {
        methods[name]
    }
}

extension NativeModules {
    subscript(name: String) -> NativeBridge? {
        bridges[name]
    }
}
