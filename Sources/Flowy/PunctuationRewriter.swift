import Foundation

/// Converts spoken punctuation commands into symbols.
///
/// Dictation engines transcribe words like "period" and "comma" literally.
/// This rewriter replaces a fixed set of command phrases with the matching
/// symbol and fixes the surrounding spacing — the same convention used by
/// macOS's own Dictation and every push-to-talk tool.
///
/// Matching is case-insensitive and phrase-aware (multi-word commands like
/// "new line" and "question mark" are matched before single words).
enum PunctuationRewriter {

    private enum Kind {
        case attach     // no space before, single space after:  .  ,  ?  !  :  ;
        case open       // space before, no space after:         (
        case close      // no space before, space after:         )
        case newline    // line break, no surrounding spaces
        case paragraph  // double line break, no surrounding spaces
    }

    private struct Command {
        let words: [String]   // lowercased, already split
        let symbol: String
        let kind: Kind
    }

    // Longer phrases first so "new paragraph" wins over "new", etc.
    private static let commands: [Command] = [
        Command(words: ["new", "paragraph"],      symbol: "\n\n", kind: .paragraph),
        Command(words: ["new", "line"],           symbol: "\n",   kind: .newline),
        Command(words: ["newline"],               symbol: "\n",   kind: .newline),
        Command(words: ["question", "mark"],      symbol: "?",    kind: .attach),
        Command(words: ["exclamation", "mark"],   symbol: "!",    kind: .attach),
        Command(words: ["exclamation", "point"],  symbol: "!",    kind: .attach),
        Command(words: ["open", "parenthesis"],   symbol: "(",    kind: .open),
        Command(words: ["close", "parenthesis"],  symbol: ")",    kind: .close),
        Command(words: ["open", "paren"],         symbol: "(",    kind: .open),
        Command(words: ["close", "paren"],        symbol: ")",    kind: .close),
        Command(words: ["full", "stop"],          symbol: ".",    kind: .attach),
        Command(words: ["period"],                symbol: ".",    kind: .attach),
        Command(words: ["comma"],                 symbol: ",",    kind: .attach),
        Command(words: ["colon"],                 symbol: ":",    kind: .attach),
        Command(words: ["semicolon"],             symbol: ";",    kind: .attach),
    ]

    private static let maxPhraseLength = 2

    static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        // Tokenise on whitespace, keeping the raw words. Punctuation already in
        // the text stays attached to its word and is handled as a normal token.
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
        guard !words.isEmpty else { return text }

        var output = ""
        var i = 0
        while i < words.count {
            var matched: Command?
            // Try the longest phrase that fits, shrinking down to one word.
            var span = min(Self.maxPhraseLength, words.count - i)
            while span >= 1 {
                let slice = words[i..<(i + span)].map { core($0) }
                if let cmd = commands.first(where: { $0.words.count == span && $0.words == slice }) {
                    matched = cmd
                    i += span
                    break
                }
                span -= 1
            }

            if let cmd = matched {
                output = append(output, symbol: cmd.symbol, kind: cmd.kind)
            } else {
                output = appendWord(output, words[i])
                i += 1
            }
        }

        return output
    }

    // MARK: – Assembly

    private static func append(_ output: String, symbol: String, kind: Kind) -> String {
        switch kind {
        case .attach, .close:
            return output.trimmedTrailingSpace() + symbol + " "
        case .open:
            let base = output.isEmpty ? output : ensureTrailingSpace(output)
            return base + symbol
        case .newline, .paragraph:
            return output.trimmedTrailingSpace() + symbol
        }
    }

    private static func appendWord(_ output: String, _ word: String) -> String {
        if output.isEmpty || output.hasSuffix("\n") || output.hasSuffix(" ") || output.hasSuffix("(") {
            return output + word
        }
        return output + " " + word
    }

    private static func ensureTrailingSpace(_ s: String) -> String {
        (s.hasSuffix(" ") || s.hasSuffix("\n")) ? s : s + " "
    }

    /// Lowercased letters/digits only — strips any punctuation the engine
    /// already attached so "comma," still matches the "comma" command.
    private static func core(_ token: String) -> String {
        token.filter { $0.isLetter || $0.isNumber }.lowercased()
    }
}

private extension String {
    func trimmedTrailingSpace() -> String {
        var s = self
        while s.hasSuffix(" ") { s.removeLast() }
        return s
    }
}
