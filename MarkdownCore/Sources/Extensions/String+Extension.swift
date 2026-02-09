//
//  String+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import CryptoKit
import Foundation

public extension String {
    var sha256Hash: String {
        SHA256.hash(data: Data(utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Overload of the String.Encoding version.
    init?(data: Data, encoding: CFStringEncodings) {
        self.init(data: data, encoding: String.Encoding(from: encoding))
    }

    /// Overload of the String.Encoding version.
    func data(using encoding: CFStringEncodings, allowLossyConversion: Bool = false) -> Data? {
        data(using: String.Encoding(from: encoding), allowLossyConversion: allowLossyConversion)
    }

    func toData(encoding: String.Encoding = .utf8) -> Data? {
        data(using: encoding)
    }

    func hasPrefixIgnoreCase(_ prefix: String) -> Bool {
        range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
    }

    func getLineBreak(defaultValue: String) -> String? {
        let CRLFs = components(separatedBy: "\r\n").count - 1
        let CRs = components(separatedBy: "\r").count - CRLFs - 1
        let LFs = components(separatedBy: "\n").count - CRLFs - 1
        let usedMost = Swift.max(CRLFs, CRs, LFs)

        switch usedMost {
        case 0: return defaultValue
        case CRLFs: return "\r\n"
        case CRs: return "\r"
        case LFs: return "\n"
        default: return nil
        }
    }
}

extension String.Encoding {
    init(from: CFStringEncodings) {
        let encoding = CFStringEncoding(from.rawValue)
        self.init(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}
