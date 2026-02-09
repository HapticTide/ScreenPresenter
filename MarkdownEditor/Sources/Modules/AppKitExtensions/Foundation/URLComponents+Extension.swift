//
//  URLComponents+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension URLComponents {
    var queryDict: [String: String]? {
        queryItems?.reduce(into: [:]) { result, item in
            result[item.name] = item.value
        }
    }
}
