import Foundation

enum AmendmentRewriter {
    // Ordered so longer/more-specific markers are matched before shorter ones
    private static let markers: [String] = [
        ", scratch that, ",
        ", no scratch that, ",
        ", no wait, ",
        ", wait no, ",
        ", no actually, ",
        ", wait actually, ",
        ", I meant ",
        ", I mean ",
        ", actually, ",
        ", actually ",
    ]

    static func apply(_ text: String) -> String {
        var current = text
        for _ in 0..<3 {
            let next = applyOnce(current)
            if next == current { break }
            current = next
        }
        return current
    }

    // Single pass: find the rightmost amendment marker and resolve it
    private static func applyOnce(_ text: String) -> String {
        var bestRange: Range<String.Index>?
        for marker in markers {
            if let range = text.range(of: marker, options: [.caseInsensitive, .backwards]) {
                if bestRange == nil || range.lowerBound > bestRange!.lowerBound {
                    bestRange = range
                }
            }
        }
        guard let range = bestRange else { return text }

        let pre = String(text[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let post = String(text[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pre.isEmpty, !post.isEmpty else { return text }

        FlowyLog.info("Amendment resolved pre='\(pre)' post='\(post)'")
        return merge(pre: pre, post: post)
    }

    // LCS-based merge: finds the longest common subsequence of words between
    // pre and post, then keeps pre up through the last shared word and appends
    // whatever post says after that shared word.
    private static func merge(pre: String, post: String) -> String {
        let preTokens = tokens(pre)
        let postTokens = tokens(post)
        guard !preTokens.isEmpty else { return post }
        guard !postTokens.isEmpty else { return pre }

        let (preIdxs, postIdxs) = lcsIndices(preTokens, postTokens)

        if preIdxs.isEmpty {
            // No common anchor: replace the tail of pre with all of post
            let keepCount = preTokens.count - postTokens.count
            if keepCount > 0 {
                return (Array(preTokens.prefix(keepCount)) + postTokens).joined(separator: " ")
            }
            return post
        }

        let lastPre = preIdxs.last!
        let lastPost = postIdxs.last!
        return (Array(preTokens.prefix(lastPre + 1))
            + Array(postTokens.dropFirst(lastPost + 1))).joined(separator: " ")
    }

    private static func tokens(_ text: String) -> [String] {
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    // Strips punctuation and lowercases for comparison only
    private static func core(_ token: String) -> String {
        token.filter { $0.isLetter || $0.isNumber }.lowercased()
    }

    // Returns parallel arrays of 0-based indices where the LCS matches occur
    private static func lcsIndices(_ a: [String], _ b: [String]) -> ([Int], [Int]) {
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = core(a[i-1]) == core(b[j-1])
                    ? dp[i-1][j-1] + 1
                    : max(dp[i-1][j], dp[i][j-1])
            }
        }
        var aIdxs: [Int] = [], bIdxs: [Int] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if core(a[i-1]) == core(b[j-1]) {
                aIdxs.append(i - 1); bIdxs.append(j - 1)
                i -= 1; j -= 1
            } else if dp[i-1][j] >= dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return (aIdxs.reversed(), bIdxs.reversed())
    }
}
