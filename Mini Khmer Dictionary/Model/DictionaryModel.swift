//
//  DictionaryModel.swift
//  Mini Khmer Dictionary
//

import AppKit
import Combine
import SwiftUI

/// Which part of the popover is showing.
enum PopoverMode: Hashable, CaseIterable {
    case lookUp
    case check
    case calculate
    case calendar
    // Everyday Cambodian conversions, each a tab of its own (ToolsView).
    case currency
    case number
    case units
    case loan
    case date
    
    var title: String {
        switch self {
            case .lookUp: "Look Up"
            case .check: "Check Spelling"
            case .calculate: "Calculator"
            case .calendar: "Calendar"
            case .currency: "Currency"
            case .number: "Khmer No."
            case .units: "Gold & Units"
            case .loan: "Loan"
            case .date: "Date"
        }
    }
    
    /// A shorter title for when the full ones don't fit across the popover.
    var shortTitle: String {
        switch self {
            case .lookUp: "Look Up"
            case .check: "Spelling"
            case .calculate: "Calc"
            case .calendar: "Calendar"
            case .currency: "Money"
            case .number: "Number"
            case .units: "Gold"
            case .loan: "Loan"
            case .date: "Date"
        }
    }
    
    /// For the narrowest tab bar.
    var icon: String {
        switch self {
            case .lookUp: "character.book.closed"
            case .check: "text.badge.checkmark"
            case .calculate: "plus.forwardslash.minus"
            case .calendar: "calendar"
            case .currency: "dollarsign.arrow.circlepath"
            case .number: "textformat.123"
            case .units: "scalemass"
            case .loan: "banknote"
            case .date: "calendar.badge.clock"
        }
    }
    
    /// The tool this tab shows, if it is one.
    var tool: ToolsView.Tool? {
        switch self {
            case .lookUp, .check, .calculate, .calendar: nil
            case .currency: .currency
            case .number: .number
            case .units: .units
            case .loan: .loan
            case .date: .date
        }
    }
}

/// Transient confirmation shown after something is put on the pasteboard.
struct CopyNotice: Equatable, Identifiable {
    let id = UUID()
    let word: String
    let includesDefinition: Bool
}

/// Everything the popover shows, and every way it can change.
///
/// The view owns no state of its own beyond focus: search text, results,
/// selection, paging and copy feedback all live here so the popover can be torn
/// down and rebuilt without losing the user's place.
///
/// This is an `ObservableObject` rather than `@Observable` because the app
/// deploys back to macOS 13, and the Observation framework starts at 14.
@MainActor
final class DictionaryModel: ObservableObject {
    /// Look-up or spell check. Lives here because the key handling in
    /// `AppDelegate` needs it as much as the view does.
    @Published var mode: PopoverMode = .lookUp
    
    /// Text in the search field. The view debounces changes before searching.
    @Published var query: String = ""
    
    @Published private(set) var entries: [DictionaryEntry] = []
    @Published private(set) var senses: [DictionarySense] = []
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var isSearching = false
    @Published private(set) var reachedEnd = false
    /// `true` when nothing matched and `entries` holds similar spellings
    /// instead (ផ្ទាងផ្ទាត់ → ផ្ទៀងផ្ទាត់).
    @Published private(set) var isShowingSimilar = false
    @Published private(set) var failureMessage: String?
    @Published private(set) var copyNotice: CopyNotice?
    
    /// Bumped whenever the search field should take focus again — the popover
    /// view is reused across openings, so `onAppear` alone is not enough.
    @Published private(set) var focusRequest = 0
    
    /// Identifier of the highlighted row.
    @Published var selection: DictionaryEntry.ID?
    
    /// What the list shows while the search field is empty.
    enum ListFilter: Hashable { case all, saved, recent }
    @Published var listFilter: ListFilter = .all
    /// Words starred with "Save", newest first.
    @Published private(set) var saved: [String] = UserDefaults.standard.stringArray(forKey: "savedWords") ?? []
    /// Words looked at recently, newest first.
    @Published private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentWords") ?? []
    @Published private(set) var wordOfTheDay: DictionaryEntry?
    /// Words that often follow the highlighted one.
    @Published private(set) var followers: [String] = []
    
    /// `true` while the query is Latin text being matched phonetically.
    var isRomanizedQuery: Bool {
        RomanizedSearch.isRomanized(query)
    }
    
    var selectedEntry: DictionaryEntry? {
        guard let selection else { return nil }
        return entries.first { $0.id == selection }
    }
    
    private let pageSize = 60
    private var store: DictionaryStore?
    private var isPaging = false
    private var copyResetTask: Task<Void, Never>?
    
    init() {
        Task {
            if let store = openStore() {
                await SpotlightManager.shared.indexDatabaseIfNeeded(store: store)
            }
        }
    }
    
    // MARK: - Loading
    
    /// Brings Look Up back after the Mac wakes, or when the popover opens to
    /// an empty list: reopens the database and runs the search again.
    func recover() async {
        if let store { try? await store.reopen() }
        failureMessage = nil
        await search()
    }
    
    /// Runs the current query from the top. Called by the view once the user
    /// stops typing. A failed read reopens the database and tries once more
    /// before showing an error.
    func search(retrying: Bool = true) async {
        guard let store = openStore() else { return }
        let requested = query
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            if requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, listFilter != .all {
                let words = listFilter == .saved ? saved : recent
                let page = try await store.entries(forWords: words)
                guard requested == query else { return }
                entries = page
                isShowingSimilar = false
                reachedEnd = true
                if selectedEntry == nil { selection = page.first?.id }
                failureMessage = nil
                return
            }
            var page = try await store.entries(matching: requested, limit: pageSize, offset: 0)
            var similar = false
            let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
            if page.isEmpty, !trimmed.isEmpty, !RomanizedSearch.isRomanized(trimmed) {
                page = try await store.similarEntries(to: trimmed, limit: 20)
                similar = !page.isEmpty
            }
            guard requested == query else { return }  // a newer keystroke already won
            entries = page
            isShowingSimilar = similar
            reachedEnd = similar || page.count < pageSize
            selection = page.first?.id
            failureMessage = nil
            if totalCount == 0 {
                totalCount = try await store.totalCount()
            }
        } catch {
            if retrying, (try? await store.reopen()) != nil {
                isSearching = false
                await search(retrying: false)
                return
            }
            entries = []
            isShowingSimilar = false
            selection = nil
            reachedEnd = true
            failureMessage = error.localizedDescription
        }
    }
    
    /// Whether Look Up is showing nothing it should be showing.
    var needsRecovery: Bool {
        !isSearching && entries.isEmpty && (failureMessage != nil || (query.isEmpty && listFilter == .all))
    }
    
    /// Appends the next page once the last row comes into view.
    func loadMore(after entry: DictionaryEntry) async {
        guard !reachedEnd, !isPaging, entry.id == entries.last?.id,
              let store = openStore() else { return }
        
        isPaging = true
        defer { isPaging = false }
        
        let requested = query
        let offset = entries.count
        do {
            let page = try await store.entries(matching: requested, limit: pageSize, offset: offset)
            guard requested == query, offset == entries.count else { return }
            entries.append(contentsOf: page)
            reachedEnd = page.count < pageSize
        } catch {
            reachedEnd = true
        }
    }
    
    /// Loads the meanings of the highlighted entry so the row can expand,
    /// and what tends to follow it.
    func loadSenses() async {
        guard let selection, let store = openStore() else {
            senses = []
            followers = []
            return
        }
        let loaded = (try? await store.senses(forEntry: selection)) ?? []
        guard selection == self.selection else { return }
        senses = loaded
        if let word = selectedEntry?.word {
            followers = (try? await store.wordsFollowing(word)) ?? []
        }
        
        // A word that stays on screen after a search counts as looked up.
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled, selection == self.selection, let word = selectedEntry?.word else { return }
        remember(word, in: &recent, key: "recentWords", limit: 50)
    }
    
    /// Loads today's word for the empty search.
    func loadWordOfTheDay() async {
        guard wordOfTheDay == nil, let store = openStore() else { return }
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        wordOfTheDay = try? await store.wordOfTheDay(day)
    }
    
    // MARK: - Saved and recent
    
    func isSaved(_ entry: DictionaryEntry) -> Bool {
        saved.contains(entry.word)
    }
    
    func toggleSaved(_ entry: DictionaryEntry) {
        if let index = saved.firstIndex(of: entry.word) {
            saved.remove(at: index)
            UserDefaults.standard.set(saved, forKey: "savedWords")
        } else {
            remember(entry.word, in: &saved, key: "savedWords", limit: 1_000)
        }
        if query.isEmpty, listFilter == .saved { Task { await search() } }
    }
    
    /// Adds a word looked at outside the popover (the quick look-up card) to
    /// Recent.
    func noteLookedUp(_ word: String) {
        remember(word, in: &recent, key: "recentWords", limit: 50)
        if query.isEmpty, listFilter == .recent { Task { await search() } }
    }

    func clearRecent() {
        recent = []
        UserDefaults.standard.set(recent, forKey: "recentWords")
        if query.isEmpty, listFilter == .recent { Task { await search() } }
    }
    
    private func remember(_ word: String, in list: inout [String], key: String, limit: Int) {
        list.removeAll { $0 == word }
        list.insert(word, at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
        UserDefaults.standard.set(list, forKey: key)
    }
    
    // MARK: - Selection
    
    func select(_ entry: DictionaryEntry) {
        selection = entry.id
    }
    
    /// Moves the highlight by `offset` rows, clamped to the loaded results.
    func moveSelection(by offset: Int) {
        guard !entries.isEmpty else { return }
        
        let target: Int
        if let current = entries.firstIndex(where: { $0.id == selection }) {
            target = min(max(current + offset, 0), entries.count - 1)
        } else {
            target = offset > 0 ? 0 : entries.count - 1
        }
        selection = entries[target].id
        
        // Keep the buffer ahead of the highlight when arrowing down a long list.
        if target >= entries.count - 5, let last = entries.last {
            Task { await loadMore(after: last) }
        }
    }
    
    func clearQuery() {
        query = ""
    }
    
    func requestSearchFocus() {
        focusRequest += 1
    }
    
    /// Switches to look-up with `word` in the search field.
    func lookUp(_ word: String) {
        mode = .lookUp
        query = word
        requestSearchFocus()
    }
    
    // MARK: - Copying
    
    /// Copies a word. Copying is always explicit — selecting a row never
    /// touches the pasteboard.
    func copy(_ entry: DictionaryEntry, includeDefinition: Bool = false) {
        selection = entry.id
        remember(entry.word, in: &recent, key: "recentWords", limit: 50)
        let text = includeDefinition ? entry.formattedForCopying(senses: senses) : entry.word
        write(text, notice: CopyNotice(word: entry.word, includesDefinition: includeDefinition))
    }
    
    /// Copies whatever is highlighted — the ⏎ / ⌘⏎ path.
    func copySelection(includeDefinition: Bool) {
        guard let entry = selectedEntry else { return }
        copy(entry, includeDefinition: includeDefinition)
    }
    
    private func write(_ text: String, notice: CopyNotice) {
        guard !text.isEmpty else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        copyNotice = notice
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Copied \(notice.word)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
        
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled, copyNotice == notice else { return }
            copyNotice = nil
        }
    }
    
    // MARK: - Store
    
    /// The one open database, shared with `SpellCheckModel`.
    func openStore() -> DictionaryStore? {
        if let store { return store }
        do {
            let opened = try DictionaryStore()
            store = opened
            return opened
        } catch {
            failureMessage = error.localizedDescription
            return nil
        }
    }
}
