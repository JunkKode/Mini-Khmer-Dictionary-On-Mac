//
//  RomanizedSearch.swift
//  Mini Khmer Dictionary
//

import Foundation

/// Matching for queries typed in Latin letters ("bong" → បង).
///
/// Every headword is transcribed to Latin at build time and reduced to a fuzzy
/// key; this type reduces what the user types the same way, so the two meet in
/// the middle. `fuzzyKey(_:)` mirrors `fuzzy_key` in Tools/khmer_romanize.py —
/// the two must stay in step, and Tools/khmer_romanize.py is the source of truth.
nonisolated enum RomanizedSearch {

    /// True when the query should be treated as romanized Khmer rather than
    /// Khmer script.
    static func isRomanized(_ query: String) -> Bool {
        query.unicodeScalars.contains { $0.value >= 0x41 && $0.value <= 0x7A && CharacterSet.letters.contains($0) }
    }

    /// Collapses a romanization to the skeleton used for matching: aspiration,
    /// voicing and vowel quality are all dropped, because people spell those
    /// however they like — `domlai` and `tomlai` are the same word.
    static func fuzzyKey(_ value: String) -> String {
        let folded = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var text = String(folded.unicodeScalars.filter { $0.value >= 97 && $0.value <= 122 })

        for (source, target) in digraphs {
            text = text.replacingOccurrences(of: source, with: target)
        }
        text = text.replacingOccurrences(of: "ng", with: "N")  // protect the velar nasal from g → k
        for (source, target) in voicing {
            text = text.replacingOccurrences(of: source, with: target)
        }
        text = text.replacingOccurrences(of: "N", with: "ng")

        // Map every vowel to a single placeholder, then collapse repeats.
        var result = ""
        result.reserveCapacity(text.count)
        var previous: Character?
        for (index, character) in text.enumerated() {
            // A leading `y` stays a consonant so យ- words (`yon`) don't collide
            // with vowel-initial ones (`oun`).
            let isVowel = vowels.contains(character) || (character == "y" && index > 0)
            let mapped = isVowel ? "a" : character
            if mapped == previous { continue }
            result.append(mapped)
            previous = mapped
        }
        return result
    }

    /// Everything but vowels and spelling variation, used to *find* matches.
    /// Lower tiers are better matches.
    static func tier(candidate: [UInt8], query: [UInt8]) -> Int? {
        if candidate == query { return 0 }
        if candidate.count > query.count, candidate.starts(with: query) { return 1 }
        if contains(candidate, query) { return 2 }
        if abs(candidate.count - query.count) <= 2,
           let distance = distance(candidate, query, limit: 2) {
            return 3 + distance
        }
        return nil
    }

    /// Plain lowercase letters, keeping vowels and voicing. Used to *rank*
    /// matches: someone who types `kom` rather than `kam` meant កុំ, even
    /// though both reduce to the same fuzzy key.
    static func comparisonKey(_ value: String) -> String {
        let folded = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return String(folded.unicodeScalars.filter { $0.value >= 97 && $0.value <= 122 })
    }

    /// Levenshtein distance, or `nil` once it is certain to exceed `limit`.
    /// Bounding matters: this runs against every headword that matched, and
    /// callers only care about small distances anyway.
    static func distance<Element: Equatable>(_ lhs: [Element], _ rhs: [Element], limit: Int) -> Int? {
        if abs(lhs.count - rhs.count) > limit { return nil }
        if lhs.isEmpty { return rhs.count <= limit ? rhs.count : nil }
        if rhs.isEmpty { return lhs.count <= limit ? lhs.count : nil }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            current[0] = i
            var rowMinimum = i
            for j in 1...rhs.count {
                let substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
                rowMinimum = min(rowMinimum, current[j])
            }
            if rowMinimum > limit { return nil }
            swap(&previous, &current)
        }
        let result = previous[rhs.count]
        return result <= limit ? result : nil
    }

    // MARK: - Details

    private static let digraphs = [("chh", "c"), ("ch", "c"), ("kh", "k"),
                                   ("ph", "p"), ("th", "t"), ("nh", "n")]
    private static let voicing = [("b", "p"), ("d", "t"), ("g", "k"), ("j", "c"),
                                  ("z", "s"), ("f", "p"), ("w", "v"), ("q", "k"), ("x", "k")]
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        let last = haystack.count - needle.count
        var start = 0
        while start <= last {
            if haystack[start] == needle[0] {
                var offset = 1
                while offset < needle.count, haystack[start + offset] == needle[offset] {
                    offset += 1
                }
                if offset == needle.count { return true }
            }
            start += 1
        }
        return false
    }
}
