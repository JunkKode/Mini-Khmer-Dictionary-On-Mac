//
//  SpellCheckModel.swift
//  Mini Khmer Dictionary
//

import AppKit
import Combine

/// State behind the Check Spelling half of the popover: the text being
/// checked, what is wrong with it, and the user's own word list.
@MainActor
final class SpellCheckModel: ObservableObject {
    /// The text in the editor. The view debounces changes before checking.
    @Published var text: String = ""

    /// Issues for `checkedText`, minus anything ignored this session.
    @Published private(set) var issues: [SpellingIssue] = []
    /// The text `issues` were computed for. Ranges are only valid while this
    /// still equals `text`.
    @Published private(set) var checkedText: String = ""
    @Published private(set) var isChecking = false
    @Published private(set) var failureMessage: String?
    @Published private(set) var didCopy = false

    @Published var selection: SpellingIssue.ID?

    /// Bumped whenever the editor should take focus again.
    @Published private(set) var focusRequest = 0

    /// Words offered for what is being typed, or for what comes next.
    @Published private(set) var completion: KhmerCompleter.Completion?
    /// Where the editor should put its caret after a completion.
    @Published private(set) var caretRequest = CaretRequest()
    /// The caret (no selection) as last reported by the editor.
    private var caret: Int?
    private var completionTask: Task<Void, Never>?
    private var completionDismissed = false

    var selectedIssue: SpellingIssue? {
        guard let selection else { return nil }
        return issues.first { $0.id == selection }
    }

    /// `issues`, but only when they still describe what is in the editor.
    var currentIssues: [SpellingIssue] {
        checkedText == text ? issues : []
    }

    private let openStore: () -> DictionaryStore?
    /// Words skipped until the app quits.
    private var ignored: Set<String> = []
    private var copyResetTask: Task<Void, Never>?

    private static let learnedWordsKey = "learnedWords"
    private var learned: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.learnedWordsKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: Self.learnedWordsKey) }
    }

    init(openStore: @escaping () -> DictionaryStore?) {
        self.openStore = openStore
    }

    // MARK: - Checking

    func check() async {
        let requested = text
        guard !requested.isEmpty else {
            issues = []
            checkedText = ""
            selection = nil
            return
        }
        guard let store = openStore() else {
            failureMessage = "The dictionary database could not be opened."
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            // The check itself runs off the store's actor: a long text can
            // take seconds, and lookups mustn't queue behind it.
            let checker = try await store.spellCheckerForChecking()
            let learnedWords = learned
            let found = await Task.detached(priority: .userInitiated) {
                checker.issues(in: requested, learned: learnedWords)
            }.value
            guard requested == text else { return }  // typing moved on
            issues = found.filter { !ignored.contains($0.word) }
            checkedText = requested
            failureMessage = nil
            // Keep the highlight on the same word if it is still wrong.
            if selectedIssue == nil {
                selection = issues.first?.id
            }
        } catch {
            failureMessage = error.localizedDescription
        }
    }

    /// Puts outside text in the editor — the Services menu path.
    func load(_ newText: String) {
        text = newText
        selection = nil
        requestFocus()
    }

    func requestFocus() {
        focusRequest += 1
    }

    // MARK: - Completion

    /// The editor reports every caret move. A collapsed caret right after
    /// Khmer text, or after a space following it, gets completions.
    func caretDidMove(to selection: NSRange, in currentText: String) {
        guard selection.length == 0, selection.location > 0 else {
            caret = nil
            completion = nil
            return
        }
        if caret != selection.location { completionDismissed = false }
        caret = selection.location
        guard !completionDismissed else { return }

        let before = (currentText as NSString).substring(to: min(selection.location, (currentText as NSString).length))
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            guard let store = self?.openStore(),
                  let checker = try? await store.spellCheckerForChecking() else { return }
            let found = await Task.detached(priority: .userInitiated) { checker.completions(before: before) }.value
            guard !Task.isCancelled, let self, self.caret == selection.location, self.text == currentText else { return }
            self.completion = found ?? nil
        }
    }

    /// Tab, or a click on a suggestion: puts `word` in place of what was
    /// typed so far.
    func acceptCompletion(_ chosen: String? = nil) {
        guard let completion, let caret, let word = chosen ?? completion.words.first else { return }
        let source = text as NSString
        let start = max(0, caret - completion.replacing)
        guard caret <= source.length else { return }
        text = source.replacingCharacters(in: NSRange(location: start, length: caret - start), with: word)
        let location = start + (word as NSString).length
        self.caret = location
        self.completion = nil
        caretRequest = CaretRequest(id: caretRequest.id + 1, location: location)
        requestFocus()
    }

    /// Escape hides the suggestions until the caret moves. Returns whether
    /// there were any.
    func dismissCompletion() -> Bool {
        guard completion != nil else { return false }
        completion = nil
        completionDismissed = true
        return true
    }

    // MARK: - Fixing

    /// Replaces the issue's word with `suggestion` and moves on to the next
    /// issue.
    func apply(_ suggestion: String, to issue: SpellingIssue) {
        guard checkedText == text,
              let range = Range(issue.range, in: text) else { return }

        let next = issues.first { $0.range.location > issue.range.location }
        let shift = (suggestion as NSString).length - issue.range.length

        text.replaceSubrange(range, with: suggestion)
        // Carry the remaining issues across the edit so the list doesn't blink
        // empty while the recheck runs.
        issues = issues.compactMap { other in
            if other.id == issue.id { return nil }
            guard other.range.location > issue.range.location else { return other }
            return SpellingIssue(
                range: NSRange(location: other.range.location + shift, length: other.range.length),
                word: other.word,
                kind: other.kind,
                suggestions: other.suggestions
            )
        }
        checkedText = text
        selection = next.map { $0.range.location + shift }
    }

    /// Adds the word to the user's dictionary for good.
    func learn(_ issue: SpellingIssue) {
        learned.insert(issue.word)
        drop(issue.word)
    }

    /// Stops reporting the word until the app quits.
    func ignore(_ issue: SpellingIssue) {
        ignored.insert(issue.word)
        drop(issue.word)
    }

    private func drop(_ word: String) {
        let index = issues.firstIndex { $0.id == selection }
        issues.removeAll { $0.word == word }
        if let index, !issues.isEmpty {
            selection = issues[min(index, issues.count - 1)].id
        } else {
            selection = nil
        }
    }

    // MARK: - Moving between issues

    func moveSelection(by offset: Int) {
        guard !issues.isEmpty else { return }
        let current = issues.firstIndex { $0.id == selection }
        let target = current.map { min(max($0 + offset, 0), issues.count - 1) } ?? 0
        selection = issues[target].id
    }

    // MARK: - Editing

    func clear() {
        text = ""
        issues = []
        checkedText = ""
        selection = nil
        requestFocus()
    }

    func paste() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        load(pasted)
    }

    func copyText() {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}
