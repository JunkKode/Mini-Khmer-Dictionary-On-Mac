//
//  DictionaryModel.swift
//  Mini Khmer Dictionary
//

import AppKit
import Combine
import SwiftUI

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
    /// Text in the search field. The view debounces changes before searching.
    @Published var query: String = ""

    @Published private(set) var entries: [DictionaryEntry] = []
    @Published private(set) var senses: [DictionarySense] = []
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var isSearching = false
    @Published private(set) var reachedEnd = false
    @Published private(set) var failureMessage: String?
    @Published private(set) var copyNotice: CopyNotice?

    /// Bumped whenever the search field should take focus again — the popover
    /// view is reused across openings, so `onAppear` alone is not enough.
    @Published private(set) var focusRequest = 0

    /// Identifier of the highlighted row.
    @Published var selection: DictionaryEntry.ID?

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

    // MARK: - Loading

    /// Runs the current query from the top. Called by the view once the user
    /// stops typing.
    func search() async {
        guard let store = openStore() else { return }
        let requested = query

        isSearching = true
        defer { isSearching = false }

        do {
            let page = try await store.entries(matching: requested, limit: pageSize, offset: 0)
            guard requested == query else { return }  // a newer keystroke already won
            entries = page
            reachedEnd = page.count < pageSize
            selection = page.first?.id
            failureMessage = nil
            if totalCount == 0 {
                totalCount = try await store.totalCount()
            }
        } catch {
            entries = []
            selection = nil
            reachedEnd = true
            failureMessage = error.localizedDescription
        }
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

    /// Loads the meanings of the highlighted entry so the row can expand.
    func loadSenses() async {
        guard let selection, let store = openStore() else {
            senses = []
            return
        }
        let loaded = (try? await store.senses(forEntry: selection)) ?? []
        guard selection == self.selection else { return }
        senses = loaded
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

    // MARK: - Copying

    /// Copies a word. Copying is always explicit — selecting a row never
    /// touches the pasteboard.
    func copy(_ entry: DictionaryEntry, includeDefinition: Bool = false) {
        selection = entry.id
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

    private func openStore() -> DictionaryStore? {
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
