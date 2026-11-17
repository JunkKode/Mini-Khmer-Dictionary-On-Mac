//
//  KhmerWordPrediction.swift
//  Mini Khmer Dictionary
//

import Foundation

/// Which words follow which in real text, from the corpus: ខ្ញុំ is most
/// often followed by បាន, នឹង, មិន …
nonisolated struct KhmerWordPairs: Sendable {
    /// Context word → following words with their score, −8·log2 P(next |
    /// context), best (lowest) first.
    private let successors: [String: [(word: String, score: UInt8)]]

    init(_ rows: [(context: String, next: [(word: String, score: UInt8)])] = []) {
        var successors: [String: [(word: String, score: UInt8)]] = [:]
        successors.reserveCapacity(rows.count)
        for (context, next) in rows where !next.isEmpty {
            successors[context] = next
        }
        self.successors = successors
    }

    /// Parses the `next` column of the `word_pairs` table: `word score` pairs
    /// separated by tabs.
    static func parse(_ column: String) -> [(word: String, score: UInt8)] {
        column.split(separator: "\t").compactMap { pair in
            let parts = pair.split(separator: " ")
            guard parts.count == 2, let score = UInt8(parts[1]) else { return nil }
            return (String(parts[0]), score)
        }
    }

    var isEmpty: Bool { successors.isEmpty }

    func following(_ word: String) -> [(word: String, score: UInt8)] {
        successors[word] ?? []
    }

    /// How strongly `second` is expected right after `first`, from 0 (no
    /// evidence) to about 10 (it follows half the time or more).
    func affinity(_ first: String?, _ second: String?) -> Int {
        guard let first, let second,
              let score = successors[first]?.first(where: { $0.word == second })?.score else { return 0 }
        return max(0, 12 - Int(score) / 4)
    }
}

/// Word completion for the Check Spelling editor: what the word being typed
/// is likely to become, and what may come after the last word.
nonisolated struct KhmerCompleter: Sendable {
    /// What to show: `words`, each replacing the last `replacing` UTF-16
    /// units before the caret (0 for a prediction of the next word).
    struct Completion: Equatable, Sendable {
        let replacing: Int
        let words: [String]
        var isPrediction: Bool { replacing == 0 }
    }

    private let keys: [[UInt16]]
    private let words: [String]
    private let frequency: [Int32]
    private let pairs: KhmerWordPairs
    private let longestWord: Int

    /// `vocabulary` is every word the checker accepts, with its usage.
    init(vocabulary: [String: Int32], pairs: KhmerWordPairs) {
        let sorted = vocabulary
            .filter { $0.key.unicodeScalars.count > 1 }
            .map { (key: Array($0.key.utf16), word: $0.key, count: $0.value) }
            .sorted { $0.key.lexicographicallyPrecedes($1.key) }
        keys = sorted.map(\.key)
        words = sorted.map(\.word)
        frequency = sorted.map(\.count)
        self.pairs = pairs
        longestWord = 12
    }

    /// Completions for the text before the caret.
    ///
    /// Khmer has no spaces, so the word being typed is found from the end:
    /// the longest run of whole clusters at the end that some longer word
    /// starts with. After a space or punctuation, the words that usually
    /// follow the last word are offered instead.
    func completions(before text: String, limit: Int = 5) -> Completion? {
        let tail = Array(text.unicodeScalars.suffix(80))
        var start = tail.count
        while start > 0, KhmerText.isWordScalar(tail[start - 1].value) { start -= 1 }
        let run = Array(tail[start...])

        if run.isEmpty {
            // Right after a space: predict from the last word typed.
            var end = tail.count
            while end > 0, tail[end - 1] == " " { end -= 1 }
            guard end < tail.count, end > 0 else { return nil }
            var wordStart = end
            while wordStart > 0, KhmerText.isWordScalar(tail[wordStart - 1].value) { wordStart -= 1 }
            guard let previous = lastWord(in: Array(tail[wordStart..<end])) else { return nil }
            let next = pairs.following(previous).prefix(limit).map(\.word)
            return next.isEmpty ? nil : Completion(replacing: 0, words: next)
        }

        let clusters = KhmerText.clusters(run)
        for count in stride(from: min(clusters.count, longestWord), through: 1, by: -1) {
            let first = clusters[clusters.count - count].lowerBound
            let prefix = String(String.UnicodeScalarView(run[first...]))
            let previous = lastWord(in: Array(run[..<first]))
            let found = completions(of: prefix, after: previous, limit: limit)
            if !found.isEmpty {
                return Completion(replacing: prefix.utf16.count, words: found)
            }
        }
        return nil
    }

    /// The known word that ends `scalars`, longest first.
    private func lastWord(in scalars: [Unicode.Scalar]) -> String? {
        guard !scalars.isEmpty else { return nil }
        let clusters = KhmerText.clusters(scalars)
        for count in stride(from: min(clusters.count, longestWord), through: 1, by: -1) {
            let word = String(String.UnicodeScalarView(scalars[clusters[clusters.count - count].lowerBound...]))
            if contains(word) { return word }
        }
        return nil
    }

    private func contains(_ word: String) -> Bool {
        let key = Array(word.utf16)
        let index = lowerBound(key)
        return index < keys.count && keys[index] == key
    }

    private func lowerBound(_ key: [UInt16]) -> Int {
        var low = 0, high = keys.count
        while low < high {
            let middle = (low + high) / 2
            if keys[middle].lexicographicallyPrecedes(key) { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// Words longer than `prefix` that start with it, ranked by how common
    /// they are and how well they follow `previous`.
    private func completions(of prefix: String, after previous: String?, limit: Int) -> [String] {
        let key = Array(prefix.utf16)
        var index = lowerBound(key)
        var ranked: [(score: Double, word: String)] = []
        var scanned = 0
        while index < keys.count, keys[index].starts(with: key), scanned < 20_000 {
            defer { index += 1; scanned += 1 }
            guard keys[index].count > key.count else { continue }
            let commonness = log2(Double(1 + max(frequency[index], 0)))
            let context = Double(pairs.affinity(previous, words[index]))
            ranked.append((commonness + context * 1.5, words[index]))
        }
        return ranked.sorted { $0.score == $1.score ? $0.word < $1.word : $0.score > $1.score }
            .prefix(limit).map(\.word)
    }
}
