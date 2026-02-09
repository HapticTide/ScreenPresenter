//
//  FileWrapper+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

extension FileWrapper {
    /// The text.* file name inside a text bundle.
    ///
    /// The example project by shinyfrog guesses the extension from UTType `net.daringfireball.markdown`,
    /// but their app (and many other apps) uses `.markdown` as the path extension.
    var textFileName: String {
        fileWrappers?.values.first {
            // The spec says path extensions can be arbitrary, but let's ignore generated html
            let filename = $0.filename?.lowercased()
            return filename?.hasPrefix("text.") == true && filename != "text.html"
        }?.filename ?? FileNames.textFile
    }
}
