//
//  Tests for the Khmer spell checker, run against the generated database.
//
//  Compiled together with Model/KhmerSpellChecker.swift by
//  Tools/test_spell_checker.sh. Pass a corpus text file as the second
//  argument to also measure how often real text gets flagged and how well
//  common misspellings are corrected.
//

import Foundation
import SQLite3

var failures = 0
var passes = 0

func check(_ condition: Bool, _ message: @autoclosure () -> String, line: Int = #line) {
    if condition {
        passes += 1
    } else {
        failures += 1
        print("FAIL (line \(line)): \(message())")
    }
}

// MARK: - Load the checker the way DictionaryStore does

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: spell-checker-tests <khmer_dict.sqlite3> [corpus text file]")
    exit(2)
}

var database: OpaquePointer?
guard sqlite3_open_v2(arguments[1], &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
    fatalError("cannot open \(arguments[1])")
}

func rows(_ sql: String, _ body: (OpaquePointer) -> Void) -> Bool {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
    defer { sqlite3_finalize(statement) }
    while sqlite3_step(statement) == SQLITE_ROW { body(statement) }
    return true
}

func text(_ statement: OpaquePointer, _ column: Int32) -> String {
    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
}

var headwords: [(String, Int32)] = []
_ = rows("SELECT word, freq FROM entries") { headwords.append((text($0, 0), sqlite3_column_int($0, 1))) }

#if BASELINE
let checker = KhmerSpellChecker(headwords: headwords)
#else
var lexicon = CorpusLexicon()
let hasCorpus = rows("SELECT word, freq, meant FROM corpus_words") { row in
    let meant = text(row, 2)
    if meant.isEmpty {
        lexicon.words.append((text(row, 0), sqlite3_column_int(row, 1)))
    } else {
        lexicon.misspellings.append((text(row, 0), meant))
    }
}
var pairRows: [(context: String, next: [(word: String, score: UInt8)])] = []
_ = rows("SELECT context, next FROM word_pairs") { pairRows.append((text($0, 0), KhmerWordPairs.parse(text($0, 1)))) }
lexicon.pairs = KhmerWordPairs(pairRows)
let started = Date()
let checker = KhmerSpellChecker(headwords: headwords, lexicon: lexicon)
print("loaded \(headwords.count) headwords, \(lexicon.words.count) corpus words, \(lexicon.misspellings.count) misspellings in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
#endif

// MARK: - Assertions

func issues(_ text: String) -> [SpellingIssue] { checker.issues(in: text) }

func expectClean(_ text: String, line: Int = #line) {
    let found = issues(text)
    check(found.isEmpty, "expected no issues in \(text), got \(found.map { "\($0.word) \($0.kind) \($0.suggestions)" })", line: line)
}

func expectFix(_ text: String, _ typed: String, _ meant: String, kind: SpellingIssue.Kind? = nil, line: Int = #line) {
    let found = issues(text)
    guard let issue = found.first(where: { $0.word == typed }) else {
        check(false, "expected \(typed) flagged in \(text), got \(found.map { "\($0.word) \($0.suggestions)" })", line: line)
        return
    }
    check(issue.suggestions.first == meant, "\(typed): expected \(meant) first, got \(issue.suggestions)", line: line)
    if let kind {
        check(issue.kind == kind, "\(typed): expected \(kind), got \(issue.kind)", line: line)
    }
}

#if !BASELINE
if hasCorpus {
    // Words in everyday use the dictionary lacks.
    for word in ["អាមេរិក", "វៀតណាម", "កូរ៉េ", "ជប៉ុន", "ស្មាតហ្វូន", "ហ្វេសប៊ុក", "អ៊ុយក្រែន"] {
        expectClean(word)
    }
    expectClean("ខ្ញុំទៅផ្សារជាមួយម្ដាយ")
    expectClean("រដ្ឋាភិបាលកម្ពុជា")

    // Misspellings common enough to be recognised outright.
    expectFix("តំលៃ", "តំលៃ", "តម្លៃ", kind: .soundAlike)
    expectFix("អោយ", "អោយ", "ឱ្យ", kind: .soundAlike)
    expectFix("ពត៌មាន", "ពត៌មាន", "ព័ត៌មាន")
    expectFix("កំលាំង", "កំលាំង", "កម្លាំង", kind: .soundAlike)
    expectFix("ចំនុច", "ចំនុច", "ចំណុច", kind: .soundAlike)
    expectFix("ជម្ងឺ", "ជម្ងឺ", "ជំងឺ", kind: .soundAlike)
    expectFix("ក៍", "ក៍", "ក៏")
    // …also inside a longer run, without taking its neighbours with it.
    expectFix("ធ្វើអោយ", "អោយ", "ឱ្យ")
    expectFix("ខ្ញុំចង់ដឹងតំលៃ", "តំលៃ", "តម្លៃ")
    expectFix("វាយតំលៃ", "វាយតំលៃ", "វាយតម្លៃ")  // a headword of its own

    // Spellings that render the same as the dictionary's.
    expectFix("ស្រ្តី", "ស្រ្តី", "ស្ត្រី", kind: .typingOrder)
    expectFix("មន្រ្តី", "មន្រ្តី", "មន្ត្រី", kind: .typingOrder)
    expectFix("ឃេីញ", "ឃេីញ", "ឃើញ", kind: .variant)
    expectFix("ទ្បើង", "ទ្បើង", "ឡើង", kind: .variant)
    expectFix("រឺ", "រឺ", "ឬ", kind: .variant)

    // Completion: the word being typed, and the next word after a space.
    let typing = checker.completions(before: "ខ្ញុំទៅផ្ស")
    check(typing?.replacing == "ផ្ស".utf16.count && typing?.words.contains("ផ្សារ") == true, "completes ផ្ស → ផ្សារ: \(String(describing: typing))")
    let next = checker.completions(before: "ខ្ញុំ ")
    check(next?.isPrediction == true && next?.words.contains("បាន") == true, "predicts after ខ្ញុំ: \(String(describing: next))")
    check(checker.completions(before: "hello ") == nil, "nothing for English")
    check(checker.completions(before: "") == nil, "nothing for empty text")

    // Splitting a selected phrase into words for the quick look-up card.
    let phrase = checker.words(in: "ខ្ញុំទៅផ្សារ")
    check(phrase.map(\.word) == ["ខ្ញុំ", "ទៅ", "ផ្សារ"] && phrase.allSatisfy(\.isKnown), "splits ខ្ញុំទៅផ្សារ: \(phrase)")
    let misspelled = checker.words(in: "ខ្ញុំចង់ដឹងតំលៃ")
    check(misspelled.last?.typed == "តំលៃ" && misspelled.last?.word == "តម្លៃ", "a misspelling gives the word meant: \(misspelled)")
    check(checker.words(in: "hello, world").isEmpty, "no words in English")
    check(checker.words(in: "ខ្ញុំ (ទៅ)").map(\.word) == ["ខ្ញុំ", "ទៅ"], "punctuation and spaces are skipped")
}
#endif

// Behaviour that predates the corpus and must not regress.
expectFix("ផ្ទាងផ្ទាត់", "ផ្ទាងផ្ទាត់", "ផ្ទៀងផ្ទាត់", kind: .soundAlike)
expectFix("ខ្ញុមទៅផ្សារ", "ខ្ញុម", "ខ្ញុំ")
expectFix("ក្តី", "ក្តី", "ក្ដី", kind: .variant)
expectClean("ព.ប្រ.")

print("\(passes) passed, \(failures) failed")

// MARK: - Measurements

guard arguments.count >= 3, let corpusText = try? String(contentsOfFile: arguments[2], encoding: .utf8) else {
    exit(failures == 0 ? 0 : 1)
}

/// Real text, as words: the corpus is space-separated, so joining a
/// sentence's tokens without spaces gives text as people write it.
let lines = corpusText.split(whereSeparator: { $0 == "\n" || $0 == "។" })
    .prefix(20_000).map { $0.split(separator: " ").joined() }
var flagged = 0
var clusters = 0
var flaggedWords: [String: Int] = [:]
let measureStart = Date()
for line in lines {
    clusters += KhmerText.clusters(Array(line.unicodeScalars)).count
    for issue in checker.issues(in: line) where issue.kind == .unknown || issue.kind == .soundAlike {
        flagged += 1
        flaggedWords[issue.word, default: 0] += 1
    }
}
print(String(format: "real text: %d lines, %d flagged (%.2f per 1,000 clusters) in %.1f s",
             lines.count, flagged, Double(flagged) * 1000 / Double(max(clusters, 1)),
             Date().timeIntervalSince(measureStart)))
print("most flagged:", flaggedWords.sorted { $0.value > $1.value }.prefix(30).map { "\($0.key)×\($0.value)" }.joined(separator: " "))

/// Synthetic misspellings: common dictionary words with one realistic mistake.
let swaps: [(String, String)] = [
    ("ម្", "ំ"), ("ំ", "ម្"), ("ណ", "ន"), ("ន", "ណ"), ("ិ", "ី"), ("ី", "ិ"), ("ុ", "ូ"), ("ូ", "ុ"),
    ("ៀ", "ា"), ("ោ", "ូ"), ("ៅ", "ៃ"), ("ល", "ឡ"), ("ឡ", "ល"), ("ទ", "ត"), ("ត", "ទ"), ("ព", "ប"),
    ("ក", "គ"), ("ស", "ះ"), ("់", ""), ("៉", ""), ("័", ""), ("្", ""),
]
let common = headwords.filter { $0.1 > 200 && $0.0.unicodeScalars.count >= 3 }.sorted { $0.1 > $1.1 }.prefix(3_000)
var trials = 0, top1 = 0, top3 = 0
for (word, _) in common {
    for (from, to) in swaps {
        guard let range = word.range(of: from) else { continue }
        let typed = word.replacingCharacters(in: range, with: to)
        guard !checker.issues(in: typed).isEmpty else { continue }  // became another real word
        let suggestions = checker.suggestions(for: typed, limit: 3)
        trials += 1
        if suggestions.first == word { top1 += 1 }
        if suggestions.contains(word) { top3 += 1 }
        break
    }
}
print(String(format: "synthetic misspellings: %d, correct first %.1f%%, in top 3 %.1f%%",
             trials, Double(top1) * 100 / Double(max(trials, 1)), Double(top3) * 100 / Double(max(trials, 1))))
exit(failures == 0 ? 0 : 1)
