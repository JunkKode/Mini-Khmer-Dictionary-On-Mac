//
//  FormulaEditor.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// The Smart calculator's input: a text view that colours formulas as they're
/// typed and passes Return, Tab and the arrow keys up to the model.
/// `TextEditor` can neither style ranges nor intercept those keys on macOS 13,
/// hence AppKit — the same reason `SpellCheckTextView` exists.
struct FormulaEditor: NSViewRepresentable {
    let text: String
    let caretRequest: CaretRequest
    let focusRequest: Int
    /// Underlined in red; `nil` while the formula is fine or merely unfinished.
    let errorRange: Range<Int>?
    let functions: FormulaFunctionRegistry
    let onChange: (String, NSRange) -> Void
    let onCommand: (FormulaEditorCommand) -> Bool

    static let font = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    private static let functionFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold)

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
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Self.font
        textView.typingAttributes = [.font: Self.font, .foregroundColor: NSColor.labelColor]
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.setAccessibilityLabel("Formula")
        textView.setAccessibilityHelp("Type an expression or a formula starting with =. Return saves it to history.")
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Programmatic changes must not echo back as edits mid-update.
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        if textView.string != text {
            textView.string = text
            // Earlier undo steps point at ranges that no longer exist.
            textView.undoManager?.removeAllActions()
        }
        // Restyling under an input method's marked text would cancel it.
        if !textView.hasMarkedText() {
            highlight(textView)
        }

        if coordinator.caretRequest != caretRequest {
            coordinator.caretRequest = caretRequest
            let location = min(caretRequest.location, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    // MARK: - Highlighting

    private func highlight(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let length = storage.length
        let whole = NSRange(location: 0, length: length)
        let tokens = FormulaLexer.tokenize(storage.string)

        storage.beginEditing()
        storage.setAttributes([.font: Self.font, .foregroundColor: NSColor.labelColor], range: whole)

        for (index, token) in tokens.enumerated() {
            let range = NSRange(location: token.range.lowerBound, length: token.range.count)
            guard NSMaxRange(range) <= length else { continue }
            var attributes: [NSAttributedString.Key: Any] = [:]

            switch token.kind {
            case .formulaPrefix:
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            case .number:
                attributes[.foregroundColor] = NSColor.systemBlue
            case .text:
                attributes[.foregroundColor] = NSColor.systemOrange
            case .identifier(let name):
                let isCall: Bool = {
                    guard index + 1 < tokens.count, case .leftParen = tokens[index + 1].kind else { return false }
                    return true
                }()
                if isCall, functions.function(named: name) != nil {
                    attributes[.foregroundColor] = NSColor.systemPurple
                    attributes[.font] = Self.functionFont
                } else if ["TRUE", "FALSE"].contains(name.uppercased()) {
                    attributes[.foregroundColor] = NSColor.systemPink
                } else {
                    attributes[.foregroundColor] = NSColor.labelColor
                }
            case .op, .separator:
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            case .leftParen, .rightParen:
                attributes[.foregroundColor] = NSColor.tertiaryLabelColor
            case .invalid:
                attributes[.foregroundColor] = NSColor.systemRed
            }
            storage.addAttributes(attributes, range: range)
        }

        if let errorRange {
            var range = NSRange(location: errorRange.lowerBound, length: errorRange.count)
            if range.length == 0, range.location > 0 { range = NSRange(location: range.location - 1, length: 1) }
            if NSMaxRange(range) <= length, range.length > 0 {
                storage.addAttributes([
                    .underlineStyle: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue,
                    .underlineColor: NSColor.systemRed,
                ], range: range)
            }
        }
        storage.endEditing()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FormulaEditor
        var focusRequest = -1
        var caretRequest = CaretRequest(id: -1)
        var isUpdating = false

        init(parent: FormulaEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            report(notification)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            report(notification)
        }

        private func report(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.onChange(textView.string, textView.selectedRange())
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertLineBreak(_:)):
                return parent.onCommand(.commit)
            case #selector(NSResponder.insertTab(_:)):
                // Tab completes; otherwise swallow it rather than type a tab.
                _ = parent.onCommand(.complete)
                return true
            case #selector(NSResponder.moveUp(_:)):
                return parent.onCommand(.moveUp)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onCommand(.moveDown)
            default:
                return false
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }

            // A formula is one line: pasted line breaks become spaces.
            if replacement.contains(where: \.isNewline) {
                let flattened = replacement
                    .components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                textView.insertText(flattened, replacementRange: range)
                return false
            }

            // Typing ")" in front of a ")" that's already balanced steps over
            // it, like a code editor — completions insert both brackets.
            if replacement == ")", range.length == 0 {
                let source = textView.string as NSString
                if range.location < source.length,
                   source.substring(with: NSRange(location: range.location, length: 1)) == ")" {
                    let text = textView.string
                    let opens = text.filter { $0 == "(" }.count
                    let closes = text.filter { $0 == ")" }.count
                    if closes >= opens {
                        textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                        return false
                    }
                }
            }
            return true
        }
    }
}
