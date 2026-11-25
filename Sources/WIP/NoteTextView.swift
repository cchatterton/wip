import NaturalLanguage
import SwiftUI

struct NoteTextView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("highlightHex") private var highlightHex = WIPStyle.defaultHighlightHex
    let text: String
    var searchQuery: String = ""
    var contactNames: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(NoteSentenceFormatter.sentences(in: text).enumerated()), id: \.offset) { _, sentence in
                Text(highlighted(sentence))
                    .font(WIPStyle.bodyFont)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func highlighted(_ sentence: String) -> AttributedString {
        let colour = WIPStyle.highlightSurface(colorScheme, hex: highlightHex)
        let source = sentence as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var matches: [NSRange] = []

        let searchTerm = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchTerm.isEmpty {
            let pattern = NSRegularExpression.escapedPattern(for: searchTerm)
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                matches = regex.matches(in: sentence, range: fullRange).map(\.range)
            }
        } else {
            for name in contactNames where !name.isEmpty {
                let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                matches.append(contentsOf: regex.matches(in: sentence, range: fullRange).map(\.range))
            }
        }
        matches.sort {
            if $0.location == $1.location { return $0.length > $1.length }
            return $0.location < $1.location
        }

        var result = AttributedString()
        var cursor = 0
        for match in matches where match.location >= cursor {
            if match.location > cursor {
                result += AttributedString(source.substring(with: NSRange(location: cursor, length: match.location - cursor)))
            }
            var name = AttributedString(source.substring(with: match))
            name.backgroundColor = colour
            result += name
            cursor = NSMaxRange(match)
        }
        if cursor < source.length {
            result += AttributedString(source.substring(from: cursor))
        }
        return result
    }
}

enum NoteSentenceFormatter {
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = line
            let pieces = tokenizer.tokens(for: line.startIndex..<line.endIndex)
                .map { String(line[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            result.append(contentsOf: pieces.isEmpty ? [line] : pieces)
        }
        return result
    }
}
