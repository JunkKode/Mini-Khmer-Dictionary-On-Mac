//
//  QuickLookupModel.swift
//  Mini Khmer Dictionary
//

import AppKit
import Combine

/// One word of a looked-up selection.
nonisolated struct QuickLookupWord: Identifiable, Sendable {
    /// More words than this and the selection is a passage, not a phrase;
    /// the rest is left for the full dictionary.
    static let maximumWords = 12

    let index: Int
    /// The text as it was selected.
    let typed: String
    /// Its dictionary entry, or `nil` when the dictionary doesn't have it.
    let entry: DictionaryEntry?
    /// `true` when `entry` is the closest spelling, not the word itself.
    var isGuess = false

    var id: Int { index }

    static func containsKhmer(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x1780...0x17FF).contains($0.value) || (0x19E0...0x19FF).contains($0.value) }
    }

    /// Whether a selection is worth a card: some Khmer, or a single Latin
    /// word that could be romanized Khmer. A paragraph of English, or the
    /// line of code an editor copies when nothing is selected, is not.
    static func isLookupable(_ text: String) -> Bool {
        if containsKhmer(text) { return true }
        return text.count <= 24 && text.allSatisfy { $0.isLetter && $0.isASCII }
    }
}

/// State of the quick look-up card: the words of the selection, which one
/// is shown, and its senses.
@MainActor
final class QuickLookupModel: ObservableObject {
    enum Phase: Equatable { case loading, ready, failed(String) }

    @Published private(set) var text = ""
    @Published private(set) var words: [QuickLookupWord] = []
    @Published private(set) var phase: Phase = .loading
    @Published var selectedIndex = 0 {
        didSet { if selectedIndex != oldValue { Task { await loadSenses() } } }
    }
    @Published private(set) var senses: [DictionarySense] = []
    @Published private(set) var copied = false

    private let dictionary: DictionaryModel
    private var copyResetTask: Task<Void, Never>?

    init(dictionary: DictionaryModel) {
        self.dictionary = dictionary
    }

    var selected: QuickLookupWord? {
        words.indices.contains(selectedIndex) ? words[selectedIndex] : nil
    }

    var isSaved: Bool {
        selected?.entry.map(dictionary.isSaved) ?? false
    }

    /// Looks `text` up and shows the first word the dictionary knows.
    func load(_ text: String) async {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        self.text = trimmed
        words = []
        senses = []
        copied = false
        phase = .loading

        guard let store = dictionary.openStore() else {
            phase = .failed("The dictionary couldn't be opened.")
            return
        }
        do {
            let found = try await store.quickLookup(trimmed)
            guard trimmed == self.text else { return }
            words = found
            selectedIndex = found.firstIndex { $0.entry != nil } ?? 0
            phase = .ready
            await loadSenses()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func select(_ word: QuickLookupWord) {
        selectedIndex = word.index
    }

    /// Steps through the words of a phrase that the dictionary knows.
    func moveSelection(by offset: Int) {
        let known = words.filter { $0.entry != nil }.map(\.index)
        guard let position = known.firstIndex(of: selectedIndex) else { return }
        let target = position + offset
        guard known.indices.contains(target) else { return }
        selectedIndex = known[target]
    }

    private func loadSenses() async {
        guard let entry = selected?.entry, let store = dictionary.openStore() else {
            senses = []
            return
        }
        let loaded = (try? await store.senses(forEntry: entry.id)) ?? []
        guard selected?.entry?.id == entry.id else { return }
        senses = loaded
        dictionary.noteLookedUp(entry.word)
    }

    func toggleSaved() {
        guard let entry = selected?.entry else { return }
        dictionary.toggleSaved(entry)
        objectWillChange.send()
    }

    /// Copies the shown word, or with `includeDefinition` the whole entry.
    func copy(includeDefinition: Bool = false) {
        guard let entry = selected?.entry else { return }
        let text = includeDefinition ? entry.formattedForCopying(senses: senses) : entry.word
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    /// What to search for when the card hands over to the full dictionary.
    var queryForDictionary: String {
        selected?.entry?.word ?? text
    }
}
