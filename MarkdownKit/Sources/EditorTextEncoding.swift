//
//  EditorTextEncoding.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

/// https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Strings/Articles/readingFiles.html#//apple_ref/doc/uid/TP40003459-SW4.
///
/// We *can*, but don't want to, include all supported encodings, which makes the UI super complicated,
/// Markdown prefers utf-8 as mentioned here: https://daringfireball.net/linked/2011/08/05/markdown-uti.
public enum EditorTextEncoding: CaseIterable, CustomStringConvertible, Codable {
    // Derived from String.Encoding
    case ascii
    case nonLossyASCII
    case utf8
    case utf16
    case utf16BigEndian
    case utf16LittleEndian
    case macOSRoman
    case isoLatin1
    case windowsLatin1

    // Derived from CFStringEncodings
    case gb18030
    case big5
    case japaneseEUC
    case shiftJIS
    case koreanEUC

    public var description: String {
        switch self {
        case .ascii: "ASCII"
        case .nonLossyASCII: "Non-lossy ASCII"
        case .utf8: "Unicode (UTF-8)"
        case .utf16: "Unicode (UTF-16)"
        case .utf16BigEndian: "Unicode (UTF-16BE)"
        case .utf16LittleEndian: "Unicode (UTF-16LE)"
        case .macOSRoman: "Western (Mac OS Roman)"
        case .isoLatin1: "Western (ISO Latin 1)"
        case .windowsLatin1: "Western (Windows Latin 1)"
        case .gb18030: "Simplified Chinese (GB 18030)"
        case .big5: "Traditional Chinese (Big 5)"
        case .japaneseEUC: "Japanese (EUC)"
        case .shiftJIS: "Japanese (Shift JIS)"
        case .koreanEUC: "Korean (EUC)"
        }
    }

    public func encode(string: String) -> Data? {
        switch self {
        case .ascii: string.data(using: .ascii)
        case .nonLossyASCII: string.data(using: .nonLossyASCII)
        case .utf8: string.data(using: .utf8)
        case .utf16: string.data(using: .utf16)
        case .utf16BigEndian: string.data(using: .utf16BigEndian)
        case .utf16LittleEndian: string.data(using: .utf16LittleEndian)
        case .macOSRoman: string.data(using: .macOSRoman)
        case .isoLatin1: string.data(using: .isoLatin1)
        case .windowsLatin1: string.data(using: .windowsCP1252)
        case .gb18030: string.data(using: .GB_18030_2000)
        case .big5: string.data(using: .big5)
        case .japaneseEUC: string.data(using: .japaneseEUC)
        case .shiftJIS: string.data(using: String.Encoding.shiftJIS)
        case .koreanEUC: string.data(using: .EUC_KR)
        }
    }

    public func decode(data: Data, guessEncoding: Bool = false) -> String {
        let defaultResult = switch self {
        case .ascii: String(data: data, encoding: .ascii)
        case .nonLossyASCII: String(data: data, encoding: .nonLossyASCII)
        case .utf8: String(data: data, encoding: .utf8)
        case .utf16: String(data: data, encoding: .utf16)
        case .utf16BigEndian: String(data: data, encoding: .utf16BigEndian)
        case .utf16LittleEndian: String(data: data, encoding: .utf16LittleEndian)
        case .macOSRoman: String(data: data, encoding: .macOSRoman)
        case .isoLatin1: String(data: data, encoding: .isoLatin1)
        case .windowsLatin1: String(data: data, encoding: .windowsCP1252)
        case .gb18030: String(data: data, encoding: .GB_18030_2000)
        case .big5: String(data: data, encoding: .big5)
        case .japaneseEUC: String(data: data, encoding: .japaneseEUC)
        case .shiftJIS: String(data: data, encoding: String.Encoding.shiftJIS)
        case .koreanEUC: String(data: data, encoding: .EUC_KR)
        }

        if let defaultResult {
            return defaultResult
        }

        if guessEncoding, let guessedResult = data.toString() {
            return guessedResult
        }

        return data.asciiText()
    }
}

public extension EditorTextEncoding {
    /// In menus, grouping cases with a separator.
    static var groupingCases: Set<Self> {
        Set([.nonLossyASCII, .utf16LittleEndian, .windowsLatin1, .big5, .shiftJIS])
    }
}

// MARK: - Private

private extension Data {
    func asciiText(unsupported: Character = ".") -> String {
        reduce(into: "") { result, byte in
            if (byte >= 32 && byte < 127) || (byte >= 160 && byte < 255) || byte == 0x0a || byte == 0x09 {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result.append(unsupported)
            }
        }
    }
}
