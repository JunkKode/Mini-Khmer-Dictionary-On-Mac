//
//  QuickCheckPanel.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// Shows the check-selection card next to the pointer (⌥⇧Space by default),
/// and puts the corrected text back in place of the selection.
@MainActor
final class QuickCheckPanelController {
    private let model: QuickCheckModel
    private let onOpenInChecker: (String) -> Void
    private var floating: FloatingPanelController!

    init(openStore: @escaping () -> DictionaryStore?, onOpenInChecker: @escaping (String) -> Void) {
        model = QuickCheckModel(openStore: openStore)
        self.onOpenInChecker = onOpenInChecker
        floating = FloatingPanelController(
            width: QuickCheckCard.width,
            height: 140,
            maximumHeight: QuickCheckCard.maximumHeight,
            accessibilityLabel: "Khmer spelling check"
        ) { [model, weak self] in
            QuickCheckCard(
                model: model,
                onReplace: { self?.replace() },
                onOpenInChecker: { self?.openInChecker() },
                onHeightChange: { self?.floating.fit(height: $0) }
            )
        }
        floating.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
    }

    var isShown: Bool {
        floating.isShown
    }

    func show(text: String) {
        model.load(text)
        floating.show()
    }

    func close() {
        floating.close()
    }

    private func replace() {
        guard model.hasChanges else { return }
        let corrected = model.text
        close()
        Task { await SelectionReader.replaceSelection(with: corrected) }
    }

    private func openInChecker() {
        let text = model.text
        close()
        onOpenInChecker(text)
    }

    /// ↑↓ move between issues, ⏎ uses the highlighted word's first fix,
    /// ⌘⏎ replaces the selection, ⌘I ignores the word.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        switch event.keyCode {
            case 126:  // up
                model.moveSelection(by: -1)
            case 125:  // down
                model.moveSelection(by: 1)
            case 36 where flags == .command, 76 where flags == .command:  // ⌘⏎
                replace()
            case 36, 76:  // ⏎
                if let issue = model.selectedIssue, let best = issue.suggestions.first {
                    model.apply(best, to: issue)
                } else if model.issues.isEmpty {
                    replace()
                }
            case 34 where flags == .command:  // ⌘I
                if let issue = model.selectedIssue { model.ignore(issue) }
            default:
                return false
        }
        return true
    }
}
