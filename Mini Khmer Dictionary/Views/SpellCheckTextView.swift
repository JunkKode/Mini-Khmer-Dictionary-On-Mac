//
//  SpellCheckTextView.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// Plain-text editor that underlines spelling issues and reports which one the
/// caret is in. `TextEditor` can't style ranges on macOS 13, hence AppKit.
struct SpellCheckTextView: NSViewRepresentable {
    @Binding var text: String
    let issues: [SpellingIssue]
    let selection: SpellingIssue.ID?
    let focusRequest: Int
    let onSelectIssue: (SpellingIssue.ID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 16)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        // Our underlines are the only ones that should show; macOS has no
        // Khmer dictionary and would flag every word.
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.setAccessibilityLabel("Text to check")
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            // Earlier undo steps point at ranges that no longer exist.
            textView.undoManager?.removeAllActions()
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selected.location, length), length: 0))
        }

        highlight(textView)

        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        if let selection, coordinator.revealedSelection != selection,
           let issue = issues.first(where: { $0.id == selection }) {
            coordinator.revealedSelection = selection
            textView.scrollRangeToVisible(issue.range)
        }
    }

    private func highlight(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.removeAttribute(.underlineStyle, range: whole)
        storage.removeAttribute(.underlineColor, range: whole)
        storage.removeAttribute(.backgroundColor, range: whole)
        for issue in issues where NSMaxRange(issue.range) <= storage.length {
            let color: NSColor = issue.kind == .unknown ? .systemRed : .systemOrange
            storage.addAttributes(
                [
                    .underlineStyle: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue,
                    .underlineColor: color,
                ],
                range: issue.range
            )
            if issue.id == selection {
                storage.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.18), range: issue.range)
            }
        }
        storage.endEditing()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SpellCheckTextView
        var focusRequest = -1
        var revealedSelection: SpellingIssue.ID?

        init(parent: SpellCheckTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        /// Clicking into an underlined word selects its issue.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  textView.string == parent.text else { return }
            let caret = textView.selectedRange().location
            if let issue = parent.issues.first(where: { NSLocationInRange(caret, $0.range) || NSMaxRange($0.range) == caret }),
               issue.id != parent.selection {
                // Clicking is how the user got here; don't scroll away from it.
                revealedSelection = issue.id
                parent.onSelectIssue(issue.id)
            }
        }
    }
}
