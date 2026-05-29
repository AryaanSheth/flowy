import Foundation

enum DictionaryRewriter {
    static func apply(_ text: String, dictionary: [String: String]) -> String {
        guard !text.isEmpty, !dictionary.isEmpty else { return text }

        let lowered = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.lowercased(), $0.value) })
        return text
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { substitute(String($0), dictionary: lowered) }
            .joined(separator: " ")
    }

    private static func substitute(_ token: String, dictionary: [String: String]) -> String {
        guard let start = token.firstIndex(where: { $0.isLetter || $0.isNumber }) else {
            return token
        }
        guard let end = token.lastIndex(where: { $0.isLetter || $0.isNumber }) else {
            return token
        }

        let coreEnd = token.index(after: end)
        let prefix = String(token[..<start])
        let core = String(token[start..<coreEnd])
        let suffix = String(token[coreEnd...])

        if let replacement = dictionary[core.lowercased()] {
            return prefix + replacement + suffix
        }
        return token
    }
}
