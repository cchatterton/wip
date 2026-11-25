import SwiftUI

enum SearchHighlight {
    static func text(_ value: String, query: String, colorScheme: ColorScheme, highlightHex: String) -> AttributedString {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty,
              let regex = try? NSRegularExpression(
                pattern: NSRegularExpression.escapedPattern(for: term),
                options: [.caseInsensitive]) else {
            return AttributedString(value)
        }

        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        var result = AttributedString()
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                result += AttributedString(source.substring(with: NSRange(
                    location: cursor, length: match.range.location - cursor)))
            }
            var highlighted = AttributedString(source.substring(with: match.range))
            highlighted.backgroundColor = WIPStyle.highlightSurface(colorScheme, hex: highlightHex)
            result += highlighted
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length {
            result += AttributedString(source.substring(from: cursor))
        }
        return result
    }
}
