//
//  Data+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension Data {
    func decodeToDataArray() -> [Data]? {
        try? PropertyListDecoder().decode([Data].self, from: self)
    }
}

public extension [Data] {
    func encodeToData() -> Data? {
        try? PropertyListEncoder().encode(self)
    }

    func appendingData(_ data: Data) -> Self {
        if contains(data) {
            return self
        }

        return self + [data]
    }
}
