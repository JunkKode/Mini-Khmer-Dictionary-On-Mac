//
//  KhmerSpellChecker.swift
//  Mini Khmer Dictionary
//

import Foundation
import os

/// A stretch of checked text the dictionary does not recognise as written.
nonisolated struct SpellingIssue: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Nothing in the dictionary is spelled this way, or close to it.
        case unknown
        /// One letter swapped for another that sounds or looks the same — ា for
        /// ៀ, ូ for ោ, ត for ដ, ំ for ម — and the result is a dictionary word.
        case soundAlike
        /// The dictionary word, with the same letters typed in another order —
        /// it usually looks right but won't search, sort or match.
        case typingOrder
        /// A recognised alternative form, e.g. ្ត where the dictionary has ្ដ.
        case variant
    }
    
    /// UTF-16 range in the text that was checked, ready for `NSTextView`.
    let range: NSRange
    let word: String
    let kind: Kind
    /// Best replacements first. Always the dictionary form for `typingOrder`
    /// and `variant`; possibly empty for `unknown`.
    let suggestions: [String]
    
    var id: Int { range.location }
}

/// What a large body of real Khmer text adds to the dictionary. Built offline
/// by `Tools/build_corpus_lexicon.sh` from a 40M-word web corpus.
nonisolated struct CorpusLexicon: Sendable {
    /// Words in everyday use that the dictionary never catalogued — places,
    /// names, loanwords, modern terms — with how often they occur.
    var words: [(word: String, frequency: Int32)] = []
    /// Spellings common enough to appear in the corpus, but which are a cheap
    /// edit away from a far more common word: តំលៃ for តម្លៃ, ពត៌មាន for
    /// ព័ត៌មាន.
    var misspellings: [(word: String, meant: String)] = []
    /// Which words follow which, for ranking corrections by their
    /// neighbours and for predicting the next word.
    var pairs = KhmerWordPairs()
}

/// Khmer has no spaces between words, so checking is segmentation first: each
/// run of Khmer letters is split into the fewest dictionary words that cover
/// it, and whatever cannot be covered is reported.
///
/// Suggestions are ranked by `KhmerConfusion`, which knows which letters
/// people mix up because they sound or look alike, so ផ្ទាងផ្ទាត់ finds
/// ផ្ទៀងផ្ទាត់ before any word that is merely one letter away. How often each
/// word is actually used — counted over a large corpus — decides between
/// candidates that are equally close.
///
/// Built once from the dictionary's headwords (a few MB) and kept for the life
/// of the app; `issues(in:)` is cheap enough to run per keystroke pause.
nonisolated final class KhmerSpellChecker: Sendable {
    /// Every accepted word → how common it is, for tie-breaking and ranking
    /// suggestions.
    private let frequency: [String: Int32]
    /// Accepted words that come from the corpus rather than the dictionary.
    /// They are trusted a little less: a dictionary reading wins a tie.
    private let corpusWords: Set<String>
    /// Known misspelling → the word meant, and what kind of mistake it is.
    private let misspellings: [String: (meant: String, kind: SpellingIssue.Kind)]
    /// Loose key → the most common headword with that key. See `KhmerText.looseKey`.
    private let looseForms: [String: String]
    /// Longest headword, in clusters; no segment needs to look further.
    private let longestWord: Int
    /// Suggestion candidates bucketed by loose-key length, so a lookup only
    /// scans words that could be within the edit limit.
    private let candidates: [Int: [Candidate]]
    private let pairs: KhmerWordPairs
    /// Built on first use: most checks never need it.
    private let completer = OSAllocatedUnfairLock<KhmerCompleter?>(initialState: nil)
    /// Suggestions already worked out, by misspelling. The same mistakes come
    /// back on every recheck while the user edits elsewhere in the text.
    private let cache = OSAllocatedUnfairLock(initialState: [String: [Ranked]]())
    
    private struct Candidate: Sendable {
        let key: [UInt16]
        let word: String
        let frequency: Int32
        let isHeadword: Bool
    }
    
    private struct Ranked: Sendable {
        let word: String
        /// Edit cost in `KhmerConfusion` units; under `KhmerConfusion.full`
        /// means every edit was a sound- or look-alike swap.
        let cost: Int
        let score: Int
    }
    
    /// Consonants that are words on their own. Every consonant is a headword
    /// (the dictionary's entry for that letter), but letting ង or ម count as a
    /// word lets them paper over mistakes: ផ្ទាងផ្ទាត់ would read as the valid
    /// ផ្ទា + ង + ផ្ទាត់. Independent vowels such as ឬ and ឯ are real words and
    /// stay allowed.
    /// អ stays too: it is the negating prefix in អលោហៈ, អសរីរាង្គ and the like.
    private static let standaloneLetters: Set<String> = ["ក", "គ", "ត", "ស", "អ"]
    
    /// Rows are `(headword, frequency)` straight from the database; entries
    /// that are proverbs, prefixes (`កម្ពុជ—`) or exclamations are cleaned or
    /// skipped here. `lexicon` widens what counts as a word beyond the
    /// dictionary, and names misspellings common enough to recognise outright.
    init(headwords: [(String, Int32)], lexicon: CorpusLexicon = CorpusLexicon()) {
        var frequency: [String: Int32] = [:]
        frequency.reserveCapacity(headwords.count + lexicon.words.count)
        for (raw, count) in headwords {
            guard let word = Self.spellable(raw) else { continue }
            frequency[word] = max(frequency[word] ?? 0, count)
        }
        var corpusWords: Set<String> = []
        for (raw, count) in lexicon.words {
            guard let word = Self.spellable(raw), frequency[word] == nil else { continue }
            frequency[word] = count
            corpusWords.insert(word)
        }
        
        var looseForms: [String: String] = [:]
        var candidates: [Int: [Candidate]] = [:]
        var longestWord = 1
        for (word, count) in frequency {
            let scalars = Array(word.unicodeScalars)
            let isHeadword = !corpusWords.contains(word)
            longestWord = max(longestWord, KhmerText.clusters(scalars).count)
            
            let key = KhmerText.looseKey(of: scalars)
            // Keep the dictionary's spelling, then the more common one; ties go
            // to the first alphabetically so the choice doesn't depend on
            // iteration order.
            if let existing = looseForms[key],
               (corpusWords.contains(existing) ? 0 : 1, frequency[existing, default: 0], word)
                >= (isHeadword ? 1 : 0, count, existing) {
                // existing wins
            } else {
                looseForms[key] = word
            }
            
            let units = Array(key.utf16)
            candidates[units.count, default: []].append(
                Candidate(key: units, word: word, frequency: count, isHeadword: isHeadword)
            )
        }
        
        var misspellings: [String: (meant: String, kind: SpellingIssue.Kind)] = [:]
        for (raw, meant) in lexicon.misspellings {
            guard let word = Self.spellable(raw), frequency[word] == nil,
                  frequency[meant] != nil else { continue }
            let typed = Array(KhmerText.looseKey(of: Array(word.unicodeScalars)).utf16)
            let target = Array(KhmerText.looseKey(of: Array(meant.unicodeScalars)).utf16)
            let cost = KhmerConfusion.distance(typed, target, limit: .max) ?? .max
            misspellings[word] = (meant, cost < KhmerConfusion.full ? .soundAlike : .unknown)
            longestWord = max(longestWord, KhmerText.clusters(Array(word.unicodeScalars)).count)
        }
        
        self.frequency = frequency
        self.corpusWords = corpusWords
        self.misspellings = misspellings
        self.looseForms = looseForms
        self.longestWord = min(longestWord, 24)
        self.candidates = candidates
        self.pairs = lexicon.pairs
    }
    
    // MARK: - Checking
    
    /// Every problem in `text`, in reading order. Words in `learned` are
    /// accepted exactly as written. Non-Khmer text is left alone.
    func issues(in text: String, learned: Set<String> = []) -> [SpellingIssue] {
        let scalars = Array(text.unicodeScalars)
        
        // UTF-16 offset of every scalar, so ranges line up with NSString.
        var offsets = [Int](repeating: 0, count: scalars.count + 1)
        for (index, scalar) in scalars.enumerated() {
            offsets[index + 1] = offsets[index] + (scalar.value > 0xFFFF ? 2 : 1)
        }
        
        var issues: [SpellingIssue] = []
        var start = 0
        while start < scalars.count {
            guard KhmerText.isWordScalar(scalars[start].value) else {
                start += 1
                continue
            }
            var end = start
            while end < scalars.count, KhmerText.isWordScalar(scalars[end].value) {
                end += 1
            }
            // A short run ending in a full stop is an abbreviation — ព.ប្រ.,
            // (គណិត.) — and isn't meant to be a word.
            let isAbbreviation = end < scalars.count && scalars[end] == "."
            && KhmerText.clusters(Array(scalars[start..<end])).count <= 3
            if !isAbbreviation {
                issues += checkRun(scalars[start..<end], offsets: offsets, learned: learned)
            }
            start = end
        }
        return issues
    }
    
    private enum Piece {
        case word
        case form(String, SpellingIssue.Kind)
        case unknown
    }
    
    private struct Segment {
        var clusters: Range<Int>
        var piece: Piece
    }
    
    /// Splits one unbroken run of Khmer into words, then turns whatever didn't
    /// fit into issues.
    ///
    /// Dynamic programming over clusters: the split with the fewest unknown
    /// clusters wins, then the one with the fewest pieces (longest words),
    /// then the more common words. Fewest-pieces is the classic Khmer word
    /// segmentation heuristic and does well for checking, where the only
    /// question is which parts no reading can explain.
    private func checkRun(
        _ run: ArraySlice<Unicode.Scalar>,
        offsets: [Int],
        learned: Set<String>
    ) -> [SpellingIssue] {
        let (clusters, segments) = segmentRun(run, learned: learned)
        return issues(in: run, clusters: clusters, segments: segments, base: run.startIndex, offsets: offsets)
    }

    /// The words of `text` in reading order, for looking up a selected
    /// phrase one word at a time. A recognised misspelling or variant gives
    /// the standard spelling (តំលៃ → តម្លៃ); what no word explains is kept as
    /// typed. Text outside Khmer runs is dropped.
    func words(in text: String) -> [(typed: String, word: String, isKnown: Bool)] {
        let scalars = Array(text.unicodeScalars)
        var words: [(typed: String, word: String, isKnown: Bool)] = []
        var start = 0
        while start < scalars.count {
            guard KhmerText.isWordScalar(scalars[start].value) else {
                start += 1
                continue
            }
            var end = start
            while end < scalars.count, KhmerText.isWordScalar(scalars[end].value) {
                end += 1
            }
            let run = scalars[start..<end]
            let (clusters, segments) = segmentRun(run, learned: [])
            for segment in segments {
                let first = start + clusters[segment.clusters.lowerBound].lowerBound
                let last = start + clusters[segment.clusters.upperBound - 1].upperBound
                let typed = String(String.UnicodeScalarView(scalars[first..<last]))
                switch segment.piece {
                    case .word: words.append((typed, typed, true))
                    case .form(let meant, _): words.append((typed, meant, true))
                    case .unknown: words.append((typed, typed, false))
                }
            }
            start = end
        }
        return words
    }

    /// Dynamic programming over clusters: the split with the fewest unknown
    /// clusters wins, then the one with the fewest pieces (longest words),
    /// then the more common words.
    private func segmentRun(
        _ run: ArraySlice<Unicode.Scalar>,
        learned: Set<String>
    ) -> (clusters: [Range<Int>], segments: [Segment]) {
        let clusters = KhmerText.clusters(Array(run))
        let base = run.startIndex
        let texts = clusters.map { String(String.UnicodeScalarView(run[(base + $0.lowerBound)..<(base + $0.upperBound)])) }
        let keys = clusters.map { KhmerText.looseKey(Array(run[(base + $0.lowerBound)..<(base + $0.upperBound)])) }
        let count = clusters.count
        
        // cost[i] is the cheapest way to cover the first i clusters.
        var cost = [Int](repeating: .max, count: count + 1)
        var step = [(from: Int, piece: Piece)](repeating: (0, .unknown), count: count + 1)
        cost[0] = 0
        
        for i in 0..<count where cost[i] != .max {
            // One cluster nobody recognises.
            relax(&cost, &step, to: i + 1, from: i, cost: cost[i] + 10_000, piece: .unknown)
            
            var word = ""
            var key = ""
            for j in (i + 1)...min(count, i + longestWord) {
                word += texts[j - 1]
                key += keys[j - 1]
                
                if learned.contains(word) {
                    relax(&cost, &step, to: j, from: i, cost: cost[i] + 100, piece: .word)
                    continue
                }
                // A bare letter only counts as a word when it is all there is
                // (an abbreviation such as ព. or ល។) or a genuine word.
                if j == i + 1, count > 1, word.unicodeScalars.count == 1,
                   !Self.standaloneLetters.contains(word),
                   !KhmerText.isIndependentVowel(word.unicodeScalars.first!.value) {
                    continue
                }
                if let seen = frequency[word] {
                    let trust = corpusWords.contains(word) ? Self.corpusWordPenalty : 0
                    relax(&cost, &step, to: j, from: i, cost: cost[i] + 100 + Self.rarity(seen) + trust, piece: .word)
                } else if let known = misspellings[word] {
                    // Priced like a rare word: the corpus wrote it as one
                    // word, so it beats reading តំលៃ as the two words តំ and លៃ.
                    relax(&cost, &step, to: j, from: i, cost: cost[i] + 120, piece: .form(known.meant, known.kind))
                } else if let form = looseForms[key] {
                    let kind = Self.kind(of: word, comparedWith: form)
                    relax(&cost, &step, to: j, from: i, cost: cost[i] + 130, piece: .form(form, kind))
                }
            }
        }
        
        var segments: [Segment] = []
        var position = count
        while position > 0 {
            let (from, piece) = step[position]
            segments.append(Segment(clusters: from..<position, piece: piece))
            position = from
        }
        segments.reverse()
        return (clusters, Self.mergingUnknowns(segments, clusters: clusters))
    }

    /// Turns the segments of one run into issues.
    private func issues(
        in run: ArraySlice<Unicode.Scalar>,
        clusters: [Range<Int>],
        segments: [Segment],
        base: Int,
        offsets: [Int]
    ) -> [SpellingIssue] {
        func scalarRange(_ segments: Range<Int>) -> Range<Int> {
            let first = base + clusters[segments.lowerBound].lowerBound
            let last = base + clusters[segments.upperBound - 1].upperBound
            return first..<last
        }
        func issue(covering scalars: Range<Int>, kind: SpellingIssue.Kind, suggestions: [String]) -> SpellingIssue {
            SpellingIssue(
                range: NSRange(location: offsets[scalars.lowerBound], length: offsets[scalars.upperBound] - offsets[scalars.lowerBound]),
                word: String(String.UnicodeScalarView(run[scalars])),
                kind: kind,
                suggestions: suggestions
            )
        }
        
        var issues: [SpellingIssue] = []
        // Segments before this index already belong to an issue.
        var free = 0
        for index in segments.indices where index >= free {
            let form: (word: String, kind: SpellingIssue.Kind)?
            switch segments[index].piece {
                case .word: continue
                case .form(let word, let kind): form = (word, kind)
                case .unknown: form = nil
            }
            
            let window = bestWindow(around: index, in: segments, from: free, includingSelf: form == nil) {
                String(String.UnicodeScalarView(run[scalarRange($0)]))
            }
            // A known alternative spelling stands unless a longer stretch
            // explains the text at least as well: អោ is a spelling of ឱ, but
            // អោយ is ឱ្យ and អោពុក is ឪពុក.
            /// The correct words either side of `range`, the context that
            /// decides between equally close corrections.
            func neighbours(of range: Range<Int>) -> (before: String?, after: String?) {
                func word(_ position: Int) -> String? {
                    guard segments.indices.contains(position), case .word = segments[position].piece else { return nil }
                    return String(String.UnicodeScalarView(run[scalarRange(segments[position].clusters)]))
                }
                return (word(range.lowerBound - 1), word(range.upperBound))
            }
            
            if let form, window.score > 0 || window.ranked.isEmpty {
                let covered = scalarRange(segments[index].clusters)
                var suggestions = [form.word]
                if form.kind == .soundAlike || form.kind == .unknown {
                    // A known misspelling: the word meant, then other readings.
                    let typed = String(String.UnicodeScalarView(run[covered]))
                    let context = neighbours(of: index..<(index + 1))
                    suggestions += inContext(rankedSuggestions(for: typed), before: context.before, after: context.after)
                        .lazy.map(\.word).filter { $0 != form.word }.prefix(4)
                }
                issues.append(issue(covering: covered, kind: form.kind, suggestions: suggestions))
                free = index + 1
                continue
            }
            
            let covered = segments[window.segments.lowerBound].clusters.lowerBound..<segments[window.segments.upperBound - 1].clusters.upperBound
            let context = neighbours(of: window.segments)
            let ranked = inContext(window.ranked, before: context.before, after: context.after)
            let soundsAlike = (ranked.first?.cost ?? .max) < KhmerConfusion.full
            issues.append(issue(
                covering: scalarRange(covered),
                kind: soundsAlike ? .soundAlike : .unknown,
                suggestions: ranked.prefix(5).map(\.word)
            ))
            free = window.segments.upperBound
        }
        return issues
    }
    
    /// The stretch around an unknown segment that best explains the mistake.
    ///
    /// The segmenter only knows what *doesn't* fit, and a mistake often lands
    /// next to text that happens to spell a real word: in ផ្ទាងផ្ទាត់ only the ង
    /// is left over, yet the word meant is all of it. So the unknown part is
    /// also tried together with up to two neighbouring words on each side.
    ///
    /// Each neighbour taken in earns back the price of one cheap edit, since a
    /// near-match on a longer dictionary word is strong evidence on its own:
    /// តំ alone is closest to ដំ, but តំលៃ is only a ំ/ម swap and a coeng
    /// away from តម្លៃ. On a tie the longer stretch wins.
    private func bestWindow(
        around index: Int,
        in segments: [Segment],
        from lowest: Int,
        includingSelf: Bool,
        text: (Range<Int>) -> String
    ) -> (segments: Range<Int>, ranked: [Ranked], score: Int) {
        var best: (segments: Range<Int>, ranked: [Ranked], score: Int, clusters: Int) =
        (index..<(index + 1), [], .max, 0)
        
        for before in 0...2 where index - before >= lowest {
            for after in 0...2 where index + after < segments.count {
                let neighbours = before + after
                if neighbours == 0, !includingSelf { continue }
                
                let window = (index - before)..<(index + after + 1)
                let clusters = segments[window.lowerBound].clusters.lowerBound..<segments[window.upperBound - 1].clusters.upperBound
                guard clusters.count <= longestWord else { continue }
                
                let ranked = rankedSuggestions(for: text(clusters))
                guard let cost = ranked.first?.cost else { continue }
                let score = cost - neighbours * KhmerConfusion.cheapestIndel
                if score < best.score || (score == best.score && clusters.count > best.clusters) {
                    best = (window, ranked, score, clusters.count)
                }
            }
        }
        return (best.segments, best.ranked, best.score)
    }
    
    private func relax(
        _ cost: inout [Int],
        _ step: inout [(from: Int, piece: Piece)],
        to index: Int,
        from origin: Int,
        cost candidate: Int,
        piece: Piece
    ) {
        guard candidate < cost[index] else { return }
        cost[index] = candidate
        step[index] = (origin, piece)
    }
    
    /// 0 for the most common words up to 20 for ones never seen in use.
    private static func rarity(_ frequency: Int32) -> Int {
        20 - Int(min(log2(Double(1 + max(frequency, 0))), 20))
    }
    
    /// Extra segmentation cost of a corpus word over a dictionary word.
    private static let corpusWordPenalty = 8
    
    /// How much a candidate's usage counts when ranking suggestions: log2 of
    /// its corpus frequency, capped so that being common can make up for about
    /// one sound-alike swap and a half, never for an unrelated letter.
    private static func commonness(_ frequency: Int32) -> Int {
        Int(min(log2(Double(1 + max(frequency, 0))), 18))
    }
    
    /// Joins neighbouring unknown clusters into one issue, and pulls in lone
    /// letters next to them, so ខ្ញុមក reads as one mistake rather than ខ្ញុម
    /// followed by the word ក.
    private static func mergingUnknowns(_ segments: [Segment], clusters: [Range<Int>]) -> [Segment] {
        func isLoneLetter(_ segment: Segment) -> Bool {
            guard case .word = segment.piece, segment.clusters.count == 1 else { return false }
            return clusters[segment.clusters.lowerBound].count == 1
        }
        func isUnknown(_ segment: Segment) -> Bool {
            if case .unknown = segment.piece { return true }
            return false
        }
        
        var segments = segments
        var changed = true
        while changed {
            changed = false
            for index in segments.indices where isLoneLetter(segments[index]) {
                let touchesUnknown = (index > 0 && isUnknown(segments[index - 1]))
                || (index + 1 < segments.count && isUnknown(segments[index + 1]))
                if touchesUnknown {
                    segments[index].piece = .unknown
                    changed = true
                }
            }
        }
        
        var merged: [Segment] = []
        for segment in segments {
            if isUnknown(segment), let last = merged.last, isUnknown(last) {
                merged[merged.count - 1].clusters = last.clusters.lowerBound..<segment.clusters.upperBound
            } else {
                merged.append(segment)
            }
        }
        return merged
    }
    
    private static func kind(of typed: String, comparedWith form: String) -> SpellingIssue.Kind {
        let typedScalars = typed.unicodeScalars.map(\.value).sorted()
        let formScalars = form.unicodeScalars.map(\.value).sorted()
        return typedScalars == formScalars ? .typingOrder : .variant
    }
    
    // MARK: - Suggestions
    
    /// Words that `word` was probably meant to be, best first. Used for the
    /// Look Up tab's "did you mean" as well as by the checker; pass
    /// `headwordsOnly` when every result must have a dictionary entry.
    func suggestions(for word: String, limit: Int = 5, headwordsOnly: Bool = false) -> [String] {
        rankedSuggestions(for: word).lazy
            .filter { !headwordsOnly || !self.corpusWords.contains($0.word) }
            .prefix(limit).map(\.word)
    }
    
    /// Re-ranks corrections by the words around them: between ទឹក and ទឺក
    /// after ផឹក, the one people actually write after ផឹក wins. Context can
    /// outweigh about one sound-alike swap, never a real spelling difference,
    /// and a known misspelling's correction keeps its place at the top.
    private func inContext(_ ranked: [Ranked], before: String?, after: String?) -> [Ranked] {
        guard !pairs.isEmpty, before != nil || after != nil, ranked.count > 1 else { return ranked }
        let pinned = ranked.first.map { $0.score == .min } ?? false
        let rest = pinned ? Array(ranked.dropFirst()) : ranked
        let adjusted = rest.enumerated().map { offset, candidate in
            let bonus = min(16, pairs.affinity(before, candidate.word) + pairs.affinity(candidate.word, after))
            return (score: candidate.score - bonus, offset: offset, candidate: candidate)
        }
            .sorted { ($0.score, $0.offset) < ($1.score, $1.offset) }
            .map(\.candidate)
        return pinned ? [ranked[0]] + adjusted : adjusted
    }
    
    // MARK: - Completion
    
    /// Words that most often follow `word`, best first.
    func wordsFollowing(_ word: String, limit: Int = 8) -> [String] {
        pairs.following(word).prefix(limit).map(\.word)
    }
    
    /// What the word before the caret is likely to become, or what usually
    /// follows the last word after a space. See `KhmerCompleter`.
    func completions(before text: String, limit: Int = 5) -> KhmerCompleter.Completion? {
        let completer = completer.withLock { cached in
            if let cached { return cached }
            let built = KhmerCompleter(vocabulary: frequency, pairs: pairs)
            cached = built
            return built
        }
        return completer.completions(before: text, limit: limit)
    }
    
    /// `suggestions(for:)` with each candidate's edit cost in `KhmerConfusion`
    /// units. For tooling that needs to judge how close a candidate is.
    func scoredSuggestions(for word: String) -> [(word: String, cost: Int)] {
        rankedSuggestions(for: word).map { ($0.word, $0.cost) }
    }
    
    /// Candidates within the edit budget, cheapest first. Costs come from
    /// `KhmerConfusion`, so a sound-alike swap is far cheaper than an arbitrary
    /// one, and how common a word is breaks ties between similar costs. A
    /// known misspelling always leads with the word it is known to mean.
    private func rankedSuggestions(for word: String) -> [Ranked] {
        if let cached = cache.withLock({ $0[word] }) { return cached }
        
        let query = Array(KhmerText.looseKey(of: Array(word.unicodeScalars)).utf16)
        guard !query.isEmpty else { return [] }
        
        let budget = KhmerConfusion.budget(forLength: query.count)
        let reach = budget / KhmerConfusion.cheapestIndel
        var ranked: [Ranked] = []
        for length in max(1, query.count - reach)...(query.count + reach) {
            for candidate in candidates[length] ?? [] {
                // A lone letter is a headword but almost never the word meant.
                if candidate.key.count == 1, query.count > 2 { continue }
                guard candidate.word != word,
                      let cost = KhmerConfusion.distance(query, candidate.key, limit: budget) else { continue }
                let trust = candidate.isHeadword ? 0 : 2
                ranked.append(Ranked(word: candidate.word, cost: cost, score: cost * 4 - Self.commonness(candidate.frequency) + trust))
            }
        }
        ranked.sort { $0.score == $1.score ? $0.word < $1.word : $0.score < $1.score }
        if let known = misspellings[word] {
            if let index = ranked.firstIndex(where: { $0.word == known.meant }) {
                let meant = ranked.remove(at: index)
                // `.min` pins it: context re-ranking leaves it first.
                ranked.insert(Ranked(word: meant.word, cost: meant.cost, score: .min), at: 0)
            } else {
                let target = Array(KhmerText.looseKey(of: Array(known.meant.unicodeScalars)).utf16)
                let cost = KhmerConfusion.distance(query, target, limit: .max) ?? budget
                ranked.insert(Ranked(word: known.meant, cost: cost, score: .min), at: 0)
            }
        }
        let result = Array(ranked.prefix(20))
        
        cache.withLock { cache in
            if cache.count > 5_000 { cache.removeAll() }
            cache[word] = result
        }
        return result
    }
    
    // MARK: - Headword cleanup
    
    /// The spellable part of a headword, or `nil` for entries that are phrases.
    static func spellable(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "!—-… ").union(.whitespaces))
        guard let first = trimmed.unicodeScalars.first,
              trimmed.unicodeScalars.allSatisfy({ KhmerText.isWordScalar($0.value) }),
              !KhmerText.isCombining(first.value) else { return nil }
        return trimmed
    }
}

/// Which Khmer letters people confuse, and how much each mistake costs.
///
/// Costs are in tenths of an ordinary edit (`full`). Swaps between letters that
/// sound the same — or look the same, like subscript ដ and ត — cost 3, so up
/// to three of them still rank ahead of a single unrelated change.
///
/// The pairs come from how Khmer is read: a vowel sign's sound depends on the
/// consonant's series, so ា after an o-series consonant (ទា "tea") is close to
/// ៀ (ទៀ "tie"), ូ to ោ, ៃ to ៅ, and so on; consonant pairs that differ only in
/// series (ក/គ, ត/ទ, ណ/ន) sound alike; final ស, ះ and ហ are all just "h"; and
/// ំ and ម both close a syllable with "m" (តំលៃ for តម្លៃ).
nonisolated enum KhmerConfusion {
    static let full = 10
    static let soundAlike = 3
    /// Aspirated vs plain (ក/ខ): heard differently, but aspiration disappears
    /// in clusters (ខ្ញុំ is said "knhom"), so it gets mixed up too.
    static let aspiration = 6
    static let cheapestIndel = 4
    
    /// How much correction a word of `length` UTF-16 units may need before
    /// a candidate stops being a plausible suggestion.
    static func budget(forLength length: Int) -> Int {
        switch length {
            case ...2: 6
            case ...4: 10
            case ...7: 16
            default: 22
        }
    }
    
    /// Consonants that sound the same; every pair within a group is cheap.
    private static let consonantGroups = [
        "កគ", "ខឃ", "ចជ", "ឆឈ", "ដឌ", "តទ", "ថធឋឍ", "ណន", "ផភ", "បព", "លឡ", "សឝឞ",
        "ដត",  // identical as subscripts, and both "t" at the end of a word
        "ឌទ",
        "សះហ",  // final "h"
        "ំម",  // final "m"
    ]
    
    private static let aspirationPairs = ["កខ", "គឃ", "ចឆ", "ជឈ", "តថ", "ទធ", "បផ", "ពភ"]
    
    /// Vowel and sign pairs that sound alike in at least one series. Pairs,
    /// not groups: ា is close to ៀ and to ័, but ៀ and ័ are not close.
    private static let vowelPairs = [
        "ាៀ", "ូោ", "ៃៅ", "ោៅ", "ិី", "ុូ", "ឹឺ", "េែ", "ែៃ", "េៃ", "ួូ", "ួោ",
        "ៀឿ", "ើឿ", "ើឺ", "ា័", "ុោ", "ិឹ", "ិេ",
        "៉៊", "់៍", "៍៏", "៍៌",  // the last two only look alike: ក៍ for ក៏, ពណ៍ for ពណ៌
    ]
    
    /// Marks that are easy to drop or add by accident: the coeng (subscript
    /// vs. final letter, ឱ្យ vs អោយ), bantoc, the series shifters, and so on.
    private static let cheapIndels: [Character: UInt8] = [
        "្": 4, "់": 4, "៉": 4, "៊": 4, "៍": 4, "៌": 4, "៎": 4, "៏": 4, "ៈ": 4,
        "័": 5, "ះ": 6, "ំ": 6,
    ]
    
    private static let blockStart: UInt16 = 0x1780
    private static let blockSize = 0x80
    
    private static let substitutionTable: [UInt8] = {
        var table = [UInt8](repeating: UInt8(full), count: blockSize * blockSize)
        for index in 0..<blockSize { table[index * blockSize + index] = 0 }
        
        func set(_ letters: String, _ cost: Int) {
            let indices = letters.unicodeScalars.map { Int($0.value) - Int(blockStart) }
            for a in indices {
                for b in indices where a != b {
                    table[a * blockSize + b] = min(table[a * blockSize + b], UInt8(cost))
                }
            }
        }
        consonantGroups.forEach { set($0, soundAlike) }
        vowelPairs.forEach { set($0, soundAlike) }
        aspirationPairs.forEach { set($0, aspiration) }
        return table
    }()
    
    private static let indelTable: [UInt8] = {
        var table = [UInt8](repeating: UInt8(full), count: blockSize)
        for (character, cost) in cheapIndels {
            table[Int(character.unicodeScalars.first!.value) - Int(blockStart)] = cost
        }
        return table
    }()
    
    @inline(__always)
    private static func substitution(_ a: UInt16, _ b: UInt16) -> Int {
        if a == b { return 0 }
        let x = Int(a) - Int(blockStart), y = Int(b) - Int(blockStart)
        guard x >= 0, x < blockSize, y >= 0, y < blockSize else { return full }
        return Int(substitutionTable[x * blockSize + y])
    }
    
    @inline(__always)
    private static func indel(_ a: UInt16) -> Int {
        let x = Int(a) - Int(blockStart)
        guard x >= 0, x < blockSize else { return full }
        return Int(indelTable[x])
    }
    
    /// Weighted edit distance between two loose keys, or `nil` once it is
    /// certain to exceed `limit`. With `confusableOnly`, every step must be
    /// one of the known confusions — a sound- or look-alike swap or an easily
    /// dropped mark — so ចំរើន reaches ចម្រើន but កំឡុង never reaches កំពុង.
    static func distance(_ lhs: [UInt16], _ rhs: [UInt16], limit: Int, confusableOnly: Bool = false) -> Int? {
        let ceiling = confusableOnly ? full - 1 : Int.max
        @inline(__always) func step(_ cost: Int) -> Int { cost > ceiling ? 1_000_000 : cost }
        
        var previous = [Int](repeating: 0, count: rhs.count + 1)
        for j in rhs.indices { previous[j + 1] = previous[j] + step(indel(rhs[j])) }
        var current = previous
        
        for i in lhs.indices {
            let removal = step(indel(lhs[i]))
            current[0] = previous[0] + removal
            var rowMinimum = current[0]
            for j in rhs.indices {
                let value = min(
                    previous[j] + step(substitution(lhs[i], rhs[j])),
                    previous[j + 1] + removal,
                    current[j] + step(indel(rhs[j]))
                )
                current[j + 1] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return nil }
            swap(&previous, &current)
        }
        let result = previous[rhs.count]
        return result <= limit ? result : nil
    }
}

/// Unicode facts about Khmer script the checker relies on.
nonisolated enum KhmerText {
    private static let coeng: UInt32 = 0x17D2
    
    /// Letters and the marks that attach to them — what a word is made of.
    /// Khmer punctuation (។ ៕ ៖ ៗ …), digits and the zero-width space all end
    /// a run.
    static func isWordScalar(_ value: UInt32) -> Bool {
        (0x1780...0x17D3).contains(value) || value == 0x17DC || value == 0x17DD
        || value == 0x200C || value == 0x200D
    }
    
    /// Vowel signs, diacritics, the coeng and invisible joiners: everything
    /// that sits on a base letter rather than starting a new one.
    static func isCombining(_ value: UInt32) -> Bool {
        (0x17B4...0x17D3).contains(value) || value == 0x17DD || value == 0x200C || value == 0x200D
    }
    
    /// ឥ ឦ ឧ … ឳ — vowels written as letters of their own.
    static func isIndependentVowel(_ value: UInt32) -> Bool {
        (0x17A3...0x17B3).contains(value)
    }
    
    /// Independent vowels spelled out the way people often type them instead,
    /// as អ plus a vowel sign: អោយ for ឱ្យ, អោពុក for ឪពុក.
    private static let independentVowels: [UInt32: [UInt32]] = [
        0x17A3: [0x17A2],          // ឣ → អ
        0x17A4: [0x17A2, 0x17B6],  // ឤ → អា
        0x17A5: [0x17A2, 0x17B7],  // ឥ → អិ
        0x17A6: [0x17A2, 0x17B8],  // ឦ → អី
        0x17A7: [0x17A2, 0x17BB],  // ឧ → អុ
        0x17A9: [0x17A2, 0x17BC],  // ឩ → អូ
        0x17AA: [0x17A2, 0x17C5],  // ឪ → អៅ
        0x17AB: [0x179A, 0x17B9],  // ឫ → រឹ
        0x17AC: [0x179A, 0x17BA],  // ឬ → រឺ
        0x17AD: [0x179B, 0x17B9],  // ឭ → លឹ
        0x17AE: [0x179B, 0x17BA],  // ឮ → លឺ
        0x17AF: [0x17A2, 0x17C2],  // ឯ → អែ
        0x17B0: [0x17A2, 0x17C3],  // ឰ → អៃ
        0x17B1: [0x17A2, 0x17C4],  // ឱ → អោ
        0x17B2: [0x17A2, 0x17C4],  // ឲ → អោ
        0x17B3: [0x17A2, 0x17C5],  // ឳ → អៅ
    ]
    
    /// Splits scalars into written clusters: a base letter with its subscripts
    /// and marks. Swift's `Character` is not enough here — it breaks after a
    /// coeng, so ក្រ would become two characters and a word boundary could
    /// land inside a stacked consonant.
    static func clusters(_ scalars: [Unicode.Scalar]) -> [Range<Int>] {
        var clusters: [Range<Int>] = []
        var start = 0
        for index in scalars.indices where index > 0 {
            let value = scalars[index].value
            if !isCombining(value), scalars[index - 1].value != coeng {
                clusters.append(start..<index)
                start = index
            }
        }
        if !scalars.isEmpty { clusters.append(start..<scalars.count) }
        return clusters
    }
    
    /// The loose key of a whole word: each cluster's key, in order.
    static func looseKey(of scalars: [Unicode.Scalar]) -> String {
        clusters(scalars).map { looseKey(Array(scalars[$0])) }.joined()
    }
    
    /// One cluster reduced so that spellings differing only in how they were
    /// typed come out the same:
    ///
    /// - marks after the subscripts are sorted and de-duplicated, so a vowel
    ///   typed before a subscript, or twice, doesn't matter;
    /// - subscript ដ and ត become the same (the dictionary mostly uses ្ដ,
    ///   most keyboards type ្ត);
    /// - subscript រ goes after any other subscript, so ស្រ្តី keys like
    ///   ស្ត្រី — the two look identical once rendered;
    /// - independent vowels are spelled out with អ (ឱ → អោ), and ឲ joins ឱ;
    ///   ឬ and ឮ are spelled រឺ and លឺ, the way they are often typed;
    /// - េ typed with ី or ា becomes the ើ or ោ it looks like, and ទ្ប
    ///   the ឡ it looks like;
    /// - invisible joiners and inherent-vowel signs are dropped.
    static func looseKey(_ cluster: [Unicode.Scalar]) -> String {
        var head: [UInt32] = []
        var marks: [UInt32] = []
        var subscriptRo = false
        
        var index = 0
        while index < cluster.count {
            let value = cluster[index].value
            if value == coeng, index + 1 < cluster.count {
                let subscripted = cluster[index + 1].value
                if subscripted == 0x179A {
                    subscriptRo = true
                } else {
                    head += [coeng, subscripted == 0x178A ? 0x178F : subscripted]
                }
                index += 2
                continue
            }
            switch value {
                case 0x200C, 0x200D, 0x17B4, 0x17B5:
                    break
                default:
                    if let spelled = independentVowels[value] {
                        // In the head, ahead of any subscript, so ឱ្យ keys as អោ្យ
                        // and sits one coeng away from អោយ.
                        head += spelled
                    } else if isCombining(value) {
                        marks.append(value)
                    } else {
                        head.append(value)
                    }
            }
            index += 1
        }
        
        if subscriptRo { head += [coeng, 0x179A] }
        // ទ្ប is how old fonts drew ឡ, and it still looks the same.
        if head.starts(with: [0x1791, coeng, 0x1794]) { head.replaceSubrange(0..<3, with: [0x17A1]) }
        var vowels = Set(marks)
        // Split vowels that render exactly like the real one: េ + ី is ើ and
        // េ + ា is ោ on screen.
        if vowels.contains(0x17C1) {
            if vowels.remove(0x17B8) != nil { vowels.remove(0x17C1); vowels.insert(0x17BE) }
            if vowels.remove(0x17B6) != nil { vowels.remove(0x17C1); vowels.insert(0x17C4) }
        }
        let scalars = (head + Array(vowels).sorted()).compactMap(Unicode.Scalar.init)
        return String(String.UnicodeScalarView(scalars))
    }
}
