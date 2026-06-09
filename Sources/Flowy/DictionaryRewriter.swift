import Foundation

enum DictionaryRewriter {
    static func apply(_ text: String, dictionary: [String: String]) -> String {
        guard !text.isEmpty, !dictionary.isEmpty else { return text }

        let entries = dictionary
            .map { (spoken: $0.key.trimmingCharacters(in: .whitespacesAndNewlines), replacement: $0.value) }
            .filter { !$0.spoken.isEmpty && !$0.replacement.isEmpty }
            .sorted {
                if $0.spoken.count == $1.spoken.count {
                    return $0.spoken < $1.spoken
                }
                return $0.spoken.count > $1.spoken.count
            }

        var result = text
        for entry in entries {
            result = replace(entry.spoken, with: entry.replacement, in: result)
        }
        return result
    }

    private static func replace(_ spoken: String, with replacement: String, in text: String) -> String {
        let escapedParts = spoken
            .split(whereSeparator: { $0.isWhitespace })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }

        guard !escapedParts.isEmpty else { return text }

        let phrasePattern = escapedParts.joined(separator: #"\s+"#)
        let pattern = #"(?i)(^|[^\p{L}\p{N}])("# + phrasePattern + #")(?=$|[^\p{L}\p{N}])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let nsText = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range(at: 2), with: replacement)
        }
        return mutable as String
    }
}
