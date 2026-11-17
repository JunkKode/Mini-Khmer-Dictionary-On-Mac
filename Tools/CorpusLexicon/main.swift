//
//  Turns the corpus word counts in khmer-text-data/khmer.db into
//  Data/khmer_corpus.tsv, which Tools/build_dictionary_db.py loads into the
//  app's database.
//
//  Compiled together with Model/KhmerSpellChecker.swift by
//  Tools/build_corpus_lexicon.sh, so words are judged with exactly the
//  segmentation and confusion costs the app uses.
//
//  The corpus is 40M words of web text. It knows how often words are really
//  used, and it knows thousands of words the dictionary never catalogued —
//  but it is also full of common misspellings (តំលៃ 3,419 times, ពត៌មាន 3,895
//  times). So every corpus word the dictionary can't already explain is
//  compared with its closest dictionary words: if one of those is a cheap
//  edit away and much more common, the corpus word is a misspelling of it;
//  otherwise, if it is common enough, it is a word.
//

import Foundation
import SQLite3

// MARK: - Settings

/// Corpus words seen fewer times than this are ignored entirely.
let minimumCount: Int32 = 5
/// How often a word the dictionary lacks must be seen to be accepted. Short
/// ones need more evidence: a one-syllable "word" is as likely a piece the
/// corpus tokenizer cut off (តំ from តំលៃ), and it could hide mistakes.
func minimumAcceptedCount(_ word: String) -> Int32 {
    switch KhmerText.clusters(Array(word.unicodeScalars)).count {
    case 1: 1_000
    case 2: 100
    default: 40
    }
}

/// Whether `candidate`, `cost` away and used `candidateCount` times, is
/// clearly what `word`, used `count` times, was meant to be.
///
/// The cheaper the edit and the longer the word, the less more common the
/// candidate has to be. Short words get the benefit of the doubt: one- and
/// two-syllable names and loanwords (ឡុង, ម៉េង, លីន) sit a letter away from
/// common words all the time, while a long word a sound-alike swap away from
/// a dictionary word (ចំរើន, សម្លេង) is almost always that word misspelled.
func isMisspelling(_ word: String, count: Int32, of candidate: String, used candidateCount: Int32, cost: Int) -> Bool {
    let ratio = Double(candidateCount) / Double(max(count, 1))
    let typed = key(word), meant = key(candidate)
    // Reachable by known confusions alone: sound-alike letters, look-alike
    // signs, dropped or added marks. No arbitrary letter changed.
    let confusable = KhmerConfusion.distance(typed, meant, limit: KhmerConfusion.full * 2, confusableOnly: true) != nil

    switch KhmerText.clusters(Array(word.unicodeScalars)).count {
    case ...2:
        // Only the easily dropped or look-alike marks may differ — អោយ for
        // ឱ្យ, ក៍ for ក៏, ជម្ងឺ for ជំងឺ — never a letter, vowel or series
        // shifter: ទ្រី and ត្រី, អេង and ឯង, ម៉ី and មី are all real.
        return confusable && essence(typed) == essence(meant) && ratio >= 2
    case 3:
        guard confusable else { return false }
        return cost < KhmerConfusion.full ? ratio >= 0.2 : ratio >= 1
    default:
        if confusable { return ratio >= 0.05 }
        switch cost {
        case ...KhmerConfusion.full: return ratio >= 1
        case ...(KhmerConfusion.full * 3 / 2): return ratio >= 10
        case ...(KhmerConfusion.full * 2): return ratio >= 50
        default: return false
        }
    }
}

func key(_ word: String) -> [UInt16] {
    Array(KhmerText.looseKey(of: Array(word.unicodeScalars)).utf16)
}

/// A loose key without the marks people drop, add or confuse by look — the
/// coeng, ៍ ៏ ៌, ៈ ះ and ័ — with ំ counted as the ម it sounds like, and
/// short and long vowels (ិ ី, ុ ូ, ឹ ឺ) and the two series shifters as one.
func essence(_ key: [UInt16]) -> [UInt16] {
    key.compactMap { unit in
        switch unit {
        case 0x17C6: return 0x1798
        case 0x17B8: return 0x17B7  // ី → ិ
        case 0x17BC: return 0x17BB  // ូ → ុ
        case 0x17BA: return 0x17B9  // ឺ → ឹ
        case 0x17CA: return 0x17C9  // ៊ → ៉
        case 0x17D2, 0x17CD, 0x17CF, 0x17CC, 0x17C8, 0x17C7, 0x17D0: return nil
        default: return unit
        }
    }
}

/// Pieces of longer words the corpus tokenizer split off: no Khmer word
/// starts with a doubled consonant such as ត្ត or ម្ម.
func isFragment(_ word: String) -> Bool {
    let scalars = Array(word.unicodeScalars)
    return scalars.count >= 3 && scalars[1].value == 0x17D2 && scalars[2] == scalars[0]
}

// MARK: - SQLite

func open(_ path: String) -> OpaquePointer {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
        fatalError("cannot open \(path)")
    }
    return handle
}

func rows(_ handle: OpaquePointer, _ sql: String, _ body: (OpaquePointer) -> Void) {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        fatalError(String(cString: sqlite3_errmsg(handle)))
    }
    defer { sqlite3_finalize(statement) }
    while sqlite3_step(statement) == SQLITE_ROW { body(statement) }
}

func text(_ statement: OpaquePointer, _ column: Int32) -> String {
    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
}

// MARK: - Load

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("usage: corpus-lexicon <corpus khmer.db> <app khmer_dict.sqlite3> <output.tsv>")
    exit(2)
}
let started = Date()

var headwords: Set<String> = []
let dictionary = open(arguments[2])
rows(dictionary, "SELECT DISTINCT word FROM entries") { row in
    if let word = KhmerSpellChecker.spellable(text(row, 0)) { headwords.insert(word) }
}
sqlite3_close(dictionary)

/// Every Khmer corpus word, with zero-width joiners and spaces removed.
var corpus: [String: Int32] = [:]
/// Corpus word ID → the cleaned Khmer word, for reading the bigram lists.
var corpusIDs: [Int32: String] = [:]
var totalTokens: Int64 = 0
let corpusDatabase = open(arguments[1])
rows(corpusDatabase, "SELECT id, word, frequency FROM words") { row in
    let raw = text(row, 1).unicodeScalars.filter { !(0x200B...0x200D).contains($0.value) }
    let count = sqlite3_column_int(row, 2)
    totalTokens += Int64(count)
    let word = String(String.UnicodeScalarView(raw))
    guard let first = raw.first, !KhmerText.isCombining(first.value),
          raw.allSatisfy({ KhmerText.isWordScalar($0.value) }) else { return }
    guard !isFragment(word) else { return }
    corpus[word, default: 0] += count
    corpusIDs[sqlite3_column_int(row, 0)] = word
}
/// Context word ID → its successors, best first, as (word ID, score) where
/// score is −8·log2 P(next | context).
var successorLists: [Int32: [(Int32, UInt8)]] = [:]
rows(corpusDatabase, "SELECT context, predictions FROM bigram_predictions") { row in
    let context = sqlite3_column_int(row, 0)
    guard corpusIDs[context] != nil, let blob = sqlite3_column_blob(row, 1) else { return }
    let bytes = UnsafeBufferPointer(start: blob.assumingMemoryBound(to: UInt8.self), count: Int(sqlite3_column_bytes(row, 1)))
    var index = 0
    func varint() -> Int32 {
        var value: Int32 = 0, shift: Int32 = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            value |= Int32(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return value
    }
    let count = varint()
    var list: [(Int32, UInt8)] = []
    for _ in 0..<count where index < bytes.count {
        let id = varint()
        guard index < bytes.count else { break }
        list.append((id, bytes[index]))
        index += 1
    }
    successorLists[context] = list
}
sqlite3_close(corpusDatabase)
print("\(headwords.count) headwords, \(corpus.count) Khmer corpus words")

// MARK: - Headword usage

// A headword's usage counts every spelling of it that differs only in how it
// was typed — ក្តី for ក្ដី, a vowel typed before a subscript — since those are
// the same word to a reader.
var headwordByKey: [String: String] = [:]
for word in headwords.sorted() {
    let key = KhmerText.looseKey(of: Array(word.unicodeScalars))
    if let existing = headwordByKey[key], corpus[existing, default: 0] >= corpus[word, default: 0] { continue }
    headwordByKey[key] = word
}
var usage: [String: Int32] = [:]
var looseVariants: Set<String> = []
for (word, count) in corpus {
    if headwords.contains(word) {
        usage[word, default: 0] += count
    } else if let headword = headwordByKey[KhmerText.looseKey(of: Array(word.unicodeScalars))] {
        usage[headword, default: 0] += count
        looseVariants.insert(word)
    }
}

// MARK: - Classify

struct Verdict {
    enum Kind { case covered, word, misspelling(String), rare }
    let word: String
    let count: Int32
    let kind: Kind
}

func classify(_ words: [(String, Int32)], with checker: KhmerSpellChecker, usage: [String: Int32]) -> [Verdict] {
    var verdicts = [Verdict?](repeating: nil, count: words.count)
    verdicts.withUnsafeMutableBufferPointer { buffer in
        let output = buffer
        DispatchQueue.concurrentPerform(iterations: words.count) { index in
            let (word, count) = words[index]
            let issues = checker.issues(in: word)
            // The dictionary already reads it as words, or as an alternative
            // spelling it knows (ក្តី, ្រ្ត for ្ត្រ): nothing to add.
            if issues.isEmpty || issues.allSatisfy({ $0.kind == .variant || $0.kind == .typingOrder }) {
                output[index] = Verdict(word: word, count: count, kind: .covered)
                return
            }
            for (candidate, cost) in checker.scoredSuggestions(for: word)
            where isMisspelling(word, count: count, of: candidate, used: usage[candidate, default: 0], cost: cost) {
                output[index] = Verdict(word: word, count: count, kind: .misspelling(candidate))
                return
            }
            output[index] = Verdict(word: word, count: count, kind: count >= minimumAcceptedCount(word) ? .word : .rare)
        }
    }
    return verdicts.map { $0! }
}

let headwordRows = headwords.map { ($0, usage[$0, default: 0]) }
let dictionaryOnly = KhmerSpellChecker(headwords: headwordRows)

let unexplained = corpus
    .filter { !headwords.contains($0.key) && !looseVariants.contains($0.key) && $0.value >= minimumCount }
    .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    .map { ($0.key, $0.value) }
print("checking \(unexplained.count) corpus words against the dictionary…")
var verdicts = classify(unexplained, with: dictionaryOnly, usage: usage)

// Second pass: an accepted word can still be a misspelling of a more common
// accepted word the dictionary lacks — អាមេរីក for អាមេរិក.
var accepted = verdicts.compactMap { verdict -> (String, Int32)? in
    if case .word = verdict.kind { return (verdict.word, verdict.count) }
    return nil
}
let widened = KhmerSpellChecker(
    headwords: headwordRows,
    lexicon: CorpusLexicon(words: accepted.map { (word: $0.0, frequency: $0.1) })
)
var combinedUsage = usage
for (word, count) in accepted { combinedUsage[word] = count }
print("rechecking \(accepted.count) accepted words against each other…")
let recheck = Dictionary(uniqueKeysWithValues: accepted.map { ($0.0, $0.1) })
let demoted: [String: String] = Dictionary(uniqueKeysWithValues: accepted.compactMap { word, count in
    for (candidate, cost) in widened.scoredSuggestions(for: word)
    where recheck[candidate] != nil && isMisspelling(word, count: count, of: candidate, used: combinedUsage[candidate, default: 0], cost: cost) {
        return (word, candidate)
    }
    return nil
})
verdicts = verdicts.map { verdict in
    guard let meant = demoted[verdict.word] else { return verdict }
    return Verdict(word: verdict.word, count: verdict.count, kind: .misspelling(meant))
}
accepted.removeAll { demoted[$0.0] != nil }

// Third pass: a corpus "word" that is really dictionary words around a known
// misspelling — ធ្វើអោយ is ធ្វើ + អោយ — is not a word of its own. Accepting
// it would hide the mistake inside every compound it appears in.
let misspelled = Dictionary(uniqueKeysWithValues: verdicts.compactMap { verdict -> (String, String)? in
    if case .misspelling(let meant) = verdict.kind { return (verdict.word, meant) }
    return nil
})
let withMistakes = KhmerSpellChecker(
    headwords: headwordRows,
    lexicon: CorpusLexicon(misspellings: misspelled.map { (word: $0.key, meant: $0.value) })
)
let seen = Dictionary(uniqueKeysWithValues: verdicts.map { ($0.word, $0.count) })
let compounds = Set(accepted.compactMap { word, count -> String? in
    let issues = withMistakes.issues(in: word)
    // The misspelling must be at least as common on its own as the compound:
    // ហ្វេសប៊ុក is not ហ្វេ plus a rare misspelling of សំបុក.
    guard !issues.isEmpty, issues.allSatisfy({ issue in
        issue.word != word && (issue.kind == .variant || issue.kind == .typingOrder
            || (misspelled[issue.word] != nil && seen[issue.word, default: 0] >= count))
    }) else {
        return nil
    }
    return word
})
print("\(compounds.count) accepted words are dictionary words around a known misspelling")
verdicts = verdicts.map { verdict in
    compounds.contains(verdict.word) ? Verdict(word: verdict.word, count: verdict.count, kind: .covered) : verdict
}
accepted.removeAll { compounds.contains($0.0) }

// A correction must itself be a word: two corpus spellings of the same name
// can each look like a misspelling of the other.
let known = headwords.union(accepted.map(\.0))
verdicts = verdicts.map { verdict in
    guard case .misspelling(let meant) = verdict.kind, !known.contains(meant) else { return verdict }
    return Verdict(word: verdict.word, count: verdict.count, kind: .rare)
}

// MARK: - Write

var lines: [String] = [
    "# Generated by Tools/build_corpus_lexicon.sh from \(totalTokens) corpus tokens. Do not edit.",
    "# kind\tword\tcount\tmeant",
    "# h = dictionary headword and its usage, w = word the dictionary lacks, m = misspelling of `meant`",
]
for (word, count) in usage.sorted(by: { $0.key < $1.key }) where count > 0 {
    lines.append("h\t\(word)\t\(count)\t")
}
var counts = (words: 0, misspellings: 0, covered: 0, rare: 0)
for verdict in verdicts.sorted(by: { $0.word < $1.word }) {
    switch verdict.kind {
    case .word:
        lines.append("w\t\(verdict.word)\t\(verdict.count)\t")
        counts.words += 1
    case .misspelling(let meant):
        lines.append("m\t\(verdict.word)\t\(verdict.count)\t\(meant)")
        counts.misspellings += 1
    case .covered: counts.covered += 1
    case .rare: counts.rare += 1
    }
}
try! (lines.joined(separator: "\n") + "\n").write(toFile: arguments[3], atomically: true, encoding: .utf8)

// MARK: - Word pairs

// Which words follow which, for ranking corrections by their neighbours and
// for predicting the next word. Only words the checker knows take part, each
// under the spelling the checker uses (ក្តី is counted as ក្ដី).
let acceptedWords = Set(verdicts.compactMap { verdict -> String? in
    if case .word = verdict.kind { return verdict.word }
    return nil
})
func vocabularyForm(_ word: String) -> String? {
    // Lone letters are mostly pieces of words the tokenizer split.
    guard word.unicodeScalars.count > 1 else { return nil }
    if headwords.contains(word) || acceptedWords.contains(word) { return word }
    return looseVariants.contains(word) ? headwordByKey[KhmerText.looseKey(of: Array(word.unicodeScalars))] : nil
}
/// A context must be this common for its successors to be worth shipping.
let minimumContextCount: Int32 = 40
let maximumSuccessors = 12
var pairs: [String: [String: UInt8]] = [:]
for (contextID, list) in successorLists {
    guard let contextWord = corpusIDs[contextID], corpus[contextWord, default: 0] >= minimumContextCount,
          let context = vocabularyForm(contextWord) else { continue }
    var next = pairs[context, default: [:]]
    for (id, score) in list {
        guard let word = corpusIDs[id].flatMap(vocabularyForm), word != context else { continue }
        next[word] = min(next[word] ?? .max, score)
    }
    pairs[context] = next
}
var pairLines = [
    "# Generated by Tools/build_corpus_lexicon.sh. Do not edit.",
    "# context<TAB>next score<TAB>next score… — score is −8·log2 P(next | context), best first",
]
var pairCount = 0
for context in pairs.keys.sorted() {
    let best = pairs[context]!.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.prefix(maximumSuccessors)
    guard !best.isEmpty else { continue }
    pairCount += best.count
    pairLines.append(([context] + best.map { "\($0.key) \($0.value)" }).joined(separator: "\t"))
}
let pairsPath = (arguments[3] as NSString).deletingLastPathComponent + "/khmer_bigrams.tsv"
try! (pairLines.joined(separator: "\n") + "\n").write(toFile: pairsPath, atomically: true, encoding: .utf8)

print("""
word pairs:           \(pairCount) after \(pairLines.count - 2) context words → \(pairsPath)
headwords with usage: \(usage.values.filter { $0 > 0 }.count)
accepted words:       \(counts.words)
misspellings:         \(counts.misspellings)
already explained:    \(counts.covered)
too rare to accept:   \(counts.rare)
wrote \(arguments[3]) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s
""")
