//
//  QuickCheckModel.swift
//  Mini Khmer Dictionary
//

import AppKit
import Combine

/// Checks text selected in another app, for the check-selection card: finds
/// the mistakes, applies fixes to a copy, and hands back the corrected text.
@MainActor
final class QuickCheckModel: ObservableObject {
    enum Phase: Equatable { case checking, ready, noKhmer, failed(String) }

    /// The text as it was selected.
    @Published private(set) var original = ""
    /// The text with the fixes applied so far.
    @Published private(set) var text = ""
    @Published private(set) var issues: [SpellingIssue] = []
    @Published private(set) var phase: Phase = .checking
    @Published var selection: SpellingIssue.ID?

    private let openStore: () -> DictionaryStore?
    /// Words skipped with Ignore, for as long as the card is open.
    private var ignored: Set<String> = []
    private var checkTask: Task<Void, Never>?

    private static let learnedWordsKey = "learnedWords"

    init(openStore: @escaping () -> DictionaryStore?) {
        self.openStore = openStore
    }

    /// Red: nothing in the dictionary explains the word, so there's no sure
    /// fix. Blue: the word meant is known.
    static func hasKnownFix(_ issue: SpellingIssue) -> Bool {
        issue.kind != .unknown && !issue.suggestions.isEmpty
    }

    var mistakeCount: Int { issues.filter { !Self.hasKnownFix($0) }.count }
    var fixCount: Int { issues.filter(Self.hasKnownFix).count }
    var hasChanges: Bool { text != original }

    var selectedIssue: SpellingIssue? {
        issues.first { $0.id == selection } ?? issues.first
    }

    func load(_ selected: String) {
        original = selected
        text = selected
        ignored = []
        issues = []
        selection = nil
        phase = QuickLookupWord.containsKhmer(selected) ? .checking : .noKhmer
        guard phase == .checking else { return }
        recheck()
    }

    private func recheck() {
        checkTask?.cancel()
        let requested = text
        checkTask = Task {
            guard let store = openStore() else {
                phase = .failed("The dictionary couldn't be opened.")
                return
            }
            do {
                let checker = try await store.spellCheckerForChecking()
                let learned = Set(UserDefaults.standard.stringArray(forKey: Self.learnedWordsKey) ?? [])
                let found = await Task.detached(priority: .userInitiated) {
                    checker.issues(in: requested, learned: learned)
                }.value
                guard !Task.isCancelled, requested == text else { return }
                let previous = selectedIssue?.word
                issues = found.filter { !ignored.contains($0.word) }
                selection = issues.first { $0.word == previous }?.id ?? issues.first?.id
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Fixing

    func apply(_ suggestion: String, to issue: SpellingIssue) {
        let replaced = (text as NSString).replacingCharacters(in: issue.range, with: suggestion)
        text = replaced
        // Ranges after this one have moved; drop the issue now so the list
        // doesn't jump, and check again.
        issues.removeAll { $0.id == issue.id }
        recheck()
    }

    /// Applies the best fix of every blue issue at once.
    func fixAll() {
        var result = text as NSString
        // Last first, so the ranges still ahead stay valid.
        for issue in issues.filter(Self.hasKnownFix).sorted(by: { $0.range.location > $1.range.location }) {
            guard let best = issue.suggestions.first, NSMaxRange(issue.range) <= result.length else { continue }
            result = result.replacingCharacters(in: issue.range, with: best) as NSString
        }
        text = result as String
        issues.removeAll(where: Self.hasKnownFix)
        recheck()
    }

    func ignore(_ issue: SpellingIssue) {
        ignored.insert(issue.word)
        issues.removeAll { $0.word == issue.word }
        if !issues.contains(where: { $0.id == selection }) { selection = issues.first?.id }
    }

    /// Accepts the word from now on, here and in Check Spelling.
    func learn(_ issue: SpellingIssue) {
        var learned = Set(UserDefaults.standard.stringArray(forKey: Self.learnedWordsKey) ?? [])
        learned.insert(issue.word)
        UserDefaults.standard.set(learned.sorted(), forKey: Self.learnedWordsKey)
        ignore(issue)
    }

    func moveSelection(by offset: Int) {
        guard !issues.isEmpty else { return }
        let current = issues.firstIndex { $0.id == selection } ?? 0
        selection = issues[min(max(current + offset, 0), issues.count - 1)].id
    }
}
