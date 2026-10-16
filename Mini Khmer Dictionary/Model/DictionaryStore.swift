//
//  DictionaryStore.swift
//  Mini Khmer Dictionary
//

import Foundation
import SQLite3

enum DictionaryStoreError: LocalizedError {
    case databaseMissing
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .databaseMissing:
            "The bundled dictionary database could not be found."
        case .sqlite(let message):
            "The dictionary database could not be read: \(message)"
        }
    }
}

/// Read-only access to the dictionary that ships inside the app bundle.
///
/// Every query runs off the main actor so typing never blocks the popover; the
/// database is opened once and kept open for the lifetime of the app.
actor DictionaryStore {
    /// Tells SQLite to copy bound strings instead of retaining our pointers.
    nonisolated(unsafe) private static let transient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    /// Columns every entry query selects, in the order `entry(from:)` reads them.
    private static let entryColumns = "id, word, pron, pos, gloss, level, roman"

    private let handle: OpaquePointer
    /// Romanization data for every headword, loaded once the first romanized
    /// query arrives and then kept for the life of the app (a few MB).
    private var romanIndex: RomanIndex?
    /// Every headword, arranged for spell checking. Built on the first check
    /// (about 0.2 s) and then kept, like `romanIndex`.
    private var spellChecker: KhmerSpellChecker?

    init() throws {
        guard let url = Bundle.main.url(forResource: "khmer_dict", withExtension: "sqlite3") else {
            throw DictionaryStoreError.databaseMissing
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close_v2(database)
            throw DictionaryStoreError.sqlite(message)
        }
        handle = database
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    // MARK: - Queries

    /// Total number of headwords, shown in the footer.
    func totalCount() throws -> Int {
        let statement = try prepare("SELECT count(*) FROM entries")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// One page of results. An empty `query` browses the dictionary in its
    /// printed order, Latin text is matched through `RomanizedSearch`, and
    /// Khmer script is matched against headwords and definitions.
    func entries(matching query: String, limit: Int, offset: Int) throws -> [DictionaryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return try browse(limit: limit, offset: offset)
        }
        if RomanizedSearch.isRomanized(trimmed) {
            return try romanizedEntries(matching: trimmed, limit: limit, offset: offset)
        }
        return try khmerEntries(matching: trimmed, limit: limit, offset: offset)
    }

    private func browse(limit: Int, offset: Int) throws -> [DictionaryEntry] {
        let statement = try prepare(
            """
            SELECT \(Self.entryColumns)
              FROM entries
             ORDER BY ord
             LIMIT ?1 OFFSET ?2
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        sqlite3_bind_int(statement, 2, Int32(offset))
        return rows(from: statement, reserving: limit)
    }

    private func khmerEntries(matching query: String, limit: Int, offset: Int) throws -> [DictionaryEntry] {
        let escaped = Self.escapedForLike(query)
        let statement = try prepare(
            """
            SELECT \(Self.entryColumns)
              FROM entries
             WHERE word LIKE ?2 ESCAPE '\\' OR senses LIKE ?2 ESCAPE '\\'
             ORDER BY CASE WHEN word = ?1 THEN 0
                           WHEN word LIKE ?3 ESCAPE '\\' THEN 1
                           WHEN word LIKE ?2 ESCAPE '\\' THEN 2
                           ELSE 3 END,
                      length(word),
                      ord
             LIMIT ?4 OFFSET ?5
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, query)
        bind(statement, 2, "%\(escaped)%")
        bind(statement, 3, "\(escaped)%")
        sqlite3_bind_int(statement, 4, Int32(limit))
        sqlite3_bind_int(statement, 5, Int32(offset))
        return rows(from: statement, reserving: limit)
    }

    /// Ranks every headword against the romanized query and fetches the best
    /// page. Scoring 41,000 short keys takes a few milliseconds, which is why
    /// this runs off the main actor.
    ///
    /// Ranking is deliberately layered: the fuzzy key decides *whether* a word
    /// matches, the full romanization decides how close it is, and only then
    /// does corpus frequency break the remaining ties. That ordering is what
    /// makes `kom` find កុំ (closest spelling) while `domlai` finds តម្លៃ
    /// (equally distant as ដំលើ, but vastly more common).
    private func romanizedEntries(matching query: String, limit: Int, offset: Int) throws -> [DictionaryEntry] {
        let fuzzy = Array(RomanizedSearch.fuzzyKey(query).utf8)
        let comparison = Array(RomanizedSearch.comparisonKey(query).utf8)
        guard !fuzzy.isEmpty else { return [] }

        let index = try loadRomanIndex()
        var ranked: [Ranking] = []
        for position in index.ids.indices {
            guard let tier = RomanizedSearch.tier(candidate: index.fuzzy[position], query: fuzzy) else { continue }
            // Anything further than three edits away ranks the same, so the
            // comparison can bail out early instead of finishing the matrix.
            let distance = RomanizedSearch.distance(index.roman[position], comparison, limit: 3) ?? 3
            ranked.append(
                Ranking(
                    score: Ranking.score(
                        tier: tier,
                        distance: distance,
                        frequency: index.frequency[position]
                    ),
                    position: position
                )
            )
        }
        ranked.sort { $0.score == $1.score ? $0.position < $1.position : $0.score < $1.score }

        let page = ranked.dropFirst(offset).prefix(limit)
        return try entries(withIDs: page.map { index.ids[$0.position] })
    }

    private func loadRomanIndex() throws -> RomanIndex {
        if let romanIndex { return romanIndex }

        let statement = try prepare("SELECT id, rkey, roman, freq FROM entries ORDER BY ord")
        defer { sqlite3_finalize(statement) }

        var index = RomanIndex()
        index.reserveCapacity(42_000)
        while sqlite3_step(statement) == SQLITE_ROW {
            index.ids.append(sqlite3_column_int(statement, 0))
            index.fuzzy.append(Array(text(statement, 1).utf8))
            index.roman.append(Array(text(statement, 2).utf8))
            index.frequency.append(sqlite3_column_int(statement, 3))
        }

        romanIndex = index
        return index
    }

    /// Fetches rows by identifier, preserving the order of `ids`.
    private func entries(withIDs ids: [Int32]) throws -> [DictionaryEntry] {
        guard !ids.isEmpty else { return [] }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let statement = try prepare(
            "SELECT \(Self.entryColumns) FROM entries WHERE id IN (\(placeholders))"
        )
        defer { sqlite3_finalize(statement) }
        for (offset, id) in ids.enumerated() {
            sqlite3_bind_int(statement, Int32(offset + 1), id)
        }

        var byID: [Int: DictionaryEntry] = [:]
        byID.reserveCapacity(ids.count)
        for entry in rows(from: statement, reserving: ids.count) {
            byID[entry.id] = entry
        }
        return ids.compactMap { byID[Int($0)] }
    }

    // MARK: - Spell checking

    /// Problems in `text`, in reading order. `learned` holds the user's own
    /// additions to the dictionary.
    func spellingIssues(in text: String, learned: Set<String>) throws -> [SpellingIssue] {
        try loadSpellChecker().issues(in: text, learned: learned)
    }

    /// Headwords that `query` was probably meant to be — sound-alike and
    /// look-alike spellings first — for when a Khmer search finds nothing.
    func similarEntries(to query: String, limit: Int) throws -> [DictionaryEntry] {
        let words = try loadSpellChecker().suggestions(for: query, limit: limit)
        guard !words.isEmpty else { return [] }

        let placeholders = Array(repeating: "?", count: words.count).joined(separator: ",")
        let statement = try prepare(
            "SELECT \(Self.entryColumns) FROM entries WHERE word IN (\(placeholders)) ORDER BY ord"
        )
        defer { sqlite3_finalize(statement) }
        for (offset, word) in words.enumerated() {
            bind(statement, Int32(offset + 1), word)
        }

        // One row per word (the first in printed order), in suggestion order.
        var byWord: [String: DictionaryEntry] = [:]
        for entry in rows(from: statement, reserving: words.count) where !byWord.keys.contains(entry.word) {
            byWord[entry.word] = entry
        }
        return words.compactMap { byWord[$0] }
    }

    private func loadSpellChecker() throws -> KhmerSpellChecker {
        if let spellChecker { return spellChecker }

        let statement = try prepare("SELECT word, freq FROM entries")
        defer { sqlite3_finalize(statement) }

        var headwords: [(String, Int32)] = []
        headwords.reserveCapacity(42_000)
        while sqlite3_step(statement) == SQLITE_ROW {
            headwords.append((text(statement, 0), sqlite3_column_int(statement, 1)))
        }

        let checker = KhmerSpellChecker(headwords: headwords)
        spellChecker = checker
        return checker
    }

    /// The numbered meanings of a single entry, decoded on demand.
    func senses(forEntry id: Int) throws -> [DictionarySense] {
        let statement = try prepare("SELECT senses FROM entries WHERE id = ?1")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(id))

        guard sqlite3_step(statement) == SQLITE_ROW else { return [] }
        let json = text(statement, 0)
        guard let data = json.data(using: .utf8), !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([DictionarySense].self, from: data)) ?? []
    }

    // MARK: - SQLite plumbing

    private func rows(from statement: OpaquePointer, reserving capacity: Int) -> [DictionaryEntry] {
        var entries: [DictionaryEntry] = []
        entries.reserveCapacity(capacity)
        while sqlite3_step(statement) == SQLITE_ROW {
            entries.append(
                DictionaryEntry(
                    id: Int(sqlite3_column_int64(statement, 0)),
                    word: text(statement, 1),
                    pronunciation: text(statement, 2),
                    partOfSpeech: text(statement, 3),
                    gloss: text(statement, 4),
                    roman: text(statement, 6),
                    isCompound: sqlite3_column_int(statement, 5) > 1
                )
            )
        }
        return entries
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw DictionaryStoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }

    /// Where one headword landed against a romanized query. Lower sorts first.
    private struct Ranking {
        let score: Int
        let position: Int

        /// Spelling distance and how common the word is are traded off against
        /// each other: one letter of distance costs about the same as being ten
        /// times rarer. That is what lets `bong` prefer បង (very common, one
        /// letter off) over ប៉ុង (spelled exactly, almost never used), while an
        /// exact match still beats a common word three letters away.
        static func score(tier: Int, distance: Int, frequency: Int32) -> Int {
            let commonness = min(log2(Double(1 + max(frequency, 0))), 12)
            let bonus = Int(commonness * 30)
            return tier * 100_000 + min(distance, 3) * 100 - bonus
        }
    }

    private struct RomanIndex {
        var ids: [Int32] = []
        var fuzzy: [[UInt8]] = []
        var roman: [[UInt8]] = []
        var frequency: [Int32] = []

        mutating func reserveCapacity(_ capacity: Int) {
            ids.reserveCapacity(capacity)
            fuzzy.reserveCapacity(capacity)
            roman.reserveCapacity(capacity)
            frequency.reserveCapacity(capacity)
        }
    }

    /// Neutralises the wildcards a user can type so `LIKE` only matches literals.
    private static func escapedForLike(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }
}
