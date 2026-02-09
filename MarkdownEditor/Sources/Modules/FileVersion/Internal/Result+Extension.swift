//
//  Result+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import DiffKit

extension Diff.Result {
    var textColor: NSColor {
        if added {
            .addedText
        } else if removed {
            .removedText
        } else {
            .labelColor
        }
    }

    var backgroundColor: NSColor? {
        if added {
            .addedBackground
        } else if removed {
            .removedBackground
        } else {
            nil
        }
    }
}

@MainActor
extension [Diff.Result] {
    var counterText: NSAttributedString {
        let text = NSMutableAttributedString(string: "")
        let addedCount = count(where: { $0.added })
        let removedCount = count(where: { $0.removed })

        if addedCount > 0 {
            text.append(NSAttributedString(
                string: " +\(addedCount) ",
                attributes: [
                    .foregroundColor: NSColor.addedText,
                    .backgroundColor: NSColor.addedBackground,
                    .font: Constants.font,
                ]
            ))

            text.append(NSAttributedString(string: " "))
        }

        if removedCount > 0 {
            text.append(NSAttributedString(
                string: " -\(removedCount) ",
                attributes: [
                    .foregroundColor: NSColor.removedText,
                    .backgroundColor: NSColor.removedBackground,
                    .font: Constants.font,
                ]
            ))
        }

        return text
    }

    func attributedText(styledNewlines: Bool) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "")
        if styledNewlines {
            for result in self {
                text.append(result.attributedText)
            }

            return text
        }

        // If styledNewlines is false (typically for words diff or chars diff),
        // lines are added separately followed by a line break without styles.
        //
        // We use showsControlCharacters to allow the background to fill the width of each line,
        // this option cannot be changed dynamically.
        for result in self {
            let lines = result.value.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                text.append(Diff.Result(
                    value: line,
                    added: result.added,
                    removed: result.removed
                ).attributedText)

                if index < lines.count - 1 {
                    text.append(NSAttributedString(string: "\n", attributes: [.font: Constants.font]))
                }
            }
        }

        return text
    }
}

// MARK: - Private

@MainActor
private extension Diff.Result {
    var attributedText: NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: Constants.font,
        ]

        if let backgroundColor {
            attributes[.backgroundColor] = backgroundColor
        }

        if removed {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = NSColor.removedText
        }

        return NSAttributedString(string: value, attributes: attributes)
    }
}

@MainActor
enum Constants {
    static let font = NSFont.monospacedSystemFont(ofSize: 12)
}
