//
//  CalculatorModel.swift
//  Mini Khmer Dictionary
//

import AppKit
import Combine
import SwiftUI

/// Keypad, formula editor, or a small grid of cells.
enum CalculatorMode: String, CaseIterable {
    case simple
    case smart
    case grid
}

/// Asks the formula editor to put the caret somewhere. The `id` changes on
/// every request, so asking for the same spot twice still moves it.
struct CaretRequest: Equatable {
    var id = 0
    var location = 0
}

/// Keys the formula editor passes up instead of handling itself.
enum FormulaEditorCommand {
    case commit      // Return
    case complete    // Tab
    case backtab     // ⇧Tab
    case moveUp
    case moveDown
}

/// Everything the Calculator tab shows. The arithmetic itself lives in
/// `FormulaEngine` and `SimpleCalculator`; this class connects them to the
/// views, the history and the pasteboard.
@MainActor
final class CalculatorModel: ObservableObject {
    @Published var mode: CalculatorMode {
        didSet {
            guard mode != oldValue else { return }
            if oldValue == .grid { grid.commit() }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            endHistoryBrowsing()
            requestFocus()
        }
    }
    
    // MARK: Simple
    
    @Published private(set) var simple = SimpleCalculator()
    /// The keypad key most recently typed on the keyboard, lit briefly.
    @Published private(set) var flashedKey: SimpleCalculator.Key?
    
    // MARK: Smart
    
    @Published private(set) var formula = ""
    @Published private(set) var calculation: FormulaCalculation = .empty
    /// The most recent successful result, shown faintly while the formula is
    /// incomplete so the panel doesn't flicker on every keystroke.
    @Published private(set) var lastValue: (value: FormulaValue, expression: String)?
    @Published private(set) var completion: FormulaCompletion?
    @Published var completionIndex = 0
    @Published private(set) var signature: FormulaSignatureHint?
    @Published private(set) var caretRequest = CaretRequest()
    
    // MARK: History and feedback
    
    @Published private(set) var history = CalculationHistory()
    /// Highlighted history row while browsing with the arrow keys.
    @Published private(set) var historySelection: CalculationRecord.ID?
    @Published private(set) var copiedText: String?
    @Published private(set) var focusRequest = 0
    
    let engine = FormulaEngine()
    var functions: FormulaFunctionRegistry { engine.functions }
    
    /// The Grid mode's cells and editing state, observed by its own views.
    let grid = GridModel()
    
    /// What the editor and result panel show. A function name still being
    /// typed, with suggestions open, reads as unfinished rather than #NAME? —
    /// `=RO` is on its way to `=ROUND(`. Dismissing the suggestions brings the
    /// real error back.
    var presentedCalculation: FormulaCalculation {
        FormulaAssistant.presenting(calculation, completion: completion)
    }
    
    /// Characters selected in the formula editor; ⌘C copies those rather than
    /// the result when there are any.
    private(set) var editorSelection = NSRange(location: 0, length: 0)
    private var completionDismissed = false
    /// Position in `history.records` while browsing with ↑/↓.
    private var historyCursor: Int?
    /// What was being typed before browsing started, restored on the way back.
    private var draft = ""
    private var copyResetTask: Task<Void, Never>?
    private var flashResetTask: Task<Void, Never>?
    
    private static let modeKey = "calculatorMode"
    
    init() {
        mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(CalculatorMode.init) ?? .smart
        grid.copyHandler = { [weak self] text in self?.copy(text) }
    }
    
    func requestFocus() {
        focusRequest += 1
    }
    
    // MARK: - Simple calculator
    
    func press(_ key: SimpleCalculator.Key, fromKeyboard: Bool = false) {
        endHistoryBrowsing()
        if let evaluation = simple.press(key) {
            record(input: evaluation.expression,
                   expression: SimpleCalculator.displayText(evaluation.expression),
                   result: evaluation.value,
                   source: .simple)
        }
        if fromKeyboard { flash(key) }
    }
    
    private func flash(_ key: SimpleCalculator.Key) {
        flashedKey = key
        flashResetTask?.cancel()
        flashResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.flashedKey = nil
        }
    }
    
    // MARK: - Formula editor
    
    /// The editor reports every edit and caret move here.
    func editorDidChange(text: String, selection: NSRange) {
        editorSelection = selection
        if text != formula {
            formula = text
            completionDismissed = false
            endHistoryBrowsing()
            evaluateFormula()
        }
        updateAssistance()
    }
    
    /// Replaces the formula from code (history, completions, examples) and
    /// moves the caret, `nil` meaning the end.
    func setFormula(_ text: String, caret: Int? = nil) {
        formula = text
        let location = caret ?? (text as NSString).length
        editorSelection = NSRange(location: location, length: 0)
        caretRequest = CaretRequest(id: caretRequest.id + 1, location: location)
        evaluateFormula()
        updateAssistance()
    }
    
    func handle(_ command: FormulaEditorCommand) -> Bool {
        switch command {
            case .commit:
                if completion != nil {
                    acceptCompletion()
                } else {
                    commitFormula()
                }
                return true
            case .complete:
                guard completion != nil else { return false }
                acceptCompletion()
                return true
            case .backtab:
                return false
            case .moveUp:
                if let completion {
                    completionIndex = (completionIndex - 1 + completion.names.count) % completion.names.count
                    return true
                }
                return browseHistory(older: true)
            case .moveDown:
                if let completion {
                    completionIndex = (completionIndex + 1) % completion.names.count
                    return true
                }
                return browseHistory(older: false)
        }
    }
    
    func acceptCompletion(_ chosen: String? = nil) {
        guard let completion else { return }
        let name = chosen ?? completion.names[min(completionIndex, completion.names.count - 1)]
        let result = FormulaAssistant.accept(name, from: completion, in: formula, registry: functions)
        setFormula(result.text, caret: result.caret)
        requestFocus()
    }
    
    /// Inserts `NAME()` at the caret, e.g. from the function menu.
    func insertFunction(_ name: String) {
        guard let function = functions.function(named: name) else { return }
        let source = formula as NSString
        let range = editorSelection.clamped(toLength: source.length)
        let insertion = function.name + "()"
        let caret = range.location + (function.name as NSString).length + (function.maximumArguments == 0 ? 2 : 1)
        setFormula(source.replacingCharacters(in: range, with: insertion), caret: caret)
        requestFocus()
    }
    
    func dismissCompletion() {
        completionDismissed = true
        completion = nil
    }
    
    private func commitFormula() {
        guard case .value(let value, let expression) = calculation else {
            if calculation != .empty { NSSound.beep() }
            return
        }
        record(input: formula.trimmingCharacters(in: .whitespacesAndNewlines),
               expression: expression,
               result: value,
               source: .smart)
    }
    
    private func evaluateFormula() {
        calculation = engine.calculate(formula)
        switch calculation {
            case .value(let value, let expression):
                lastValue = (value, expression)
            case .empty:
                lastValue = nil
            case .failure:
                break
        }
    }
    
    private func updateAssistance() {
        let caret = editorSelection.location
        let found = (editorSelection.length == 0 && !completionDismissed)
        ? FormulaAssistant.completion(in: formula, caret: caret, registry: functions)
        : nil
        if found?.names != completion?.names { completionIndex = 0 }
        completion = found
        signature = FormulaAssistant.signature(in: formula, caret: caret, registry: functions)
    }
    
    // MARK: - History
    
    private func record(input: String, expression: String, result: FormulaValue, source: CalculationRecord.Source) {
        history.add(CalculationRecord(input: input, expression: expression, result: result, source: source))
    }
    
    /// Puts a past calculation back in front of the user — on the keypad when
    /// it's simple enough and the keypad is showing, otherwise in the editor.
    func reuse(_ record: CalculationRecord) {
        endHistoryBrowsing()
        load(record)
        requestFocus()
    }
    
    func removeFromHistory(_ record: CalculationRecord) {
        history.remove(record.id)
        if historySelection == record.id { endHistoryBrowsing() }
    }
    
    func clearHistory() {
        history.clear()
        endHistoryBrowsing()
    }
    
    /// ↑ (older) and ↓ (newer) step through history, then back to the draft.
    func browseHistory(older: Bool) -> Bool {
        let records = history.records.filter { mode == .smart || SimpleCalculator.canLoad($0.input) }
        guard !records.isEmpty else { return false }
        
        let next: Int
        if let cursor = historyCursor {
            next = cursor + (older ? 1 : -1)
        } else {
            guard older else { return false }
            draft = mode == .smart ? formula : simple.expression
            next = 0
        }
        
        if next < 0 {
            historyCursor = nil
            historySelection = nil
            if mode == .smart {
                setFormula(draft)
            } else if !simple.load(draft) {
                simple = SimpleCalculator()
            }
            return true
        }
        let index = min(next, records.count - 1)
        historyCursor = index
        historySelection = records[index].id
        load(records[index])
        return true
    }
    
    private func load(_ record: CalculationRecord) {
        if mode == .simple, SimpleCalculator.canLoad(record.input) {
            simple.load(record.input)
        } else {
            if mode != .smart {
                mode = .smart
            }
            setFormula(record.input)
        }
    }
    
    private func endHistoryBrowsing() {
        historyCursor = nil
        historySelection = nil
    }
    
    // MARK: - Escape
    
    /// Escape backs out one step at a time. Returns false when there was
    /// nothing left to clear, so the caller can close the popover.
    func handleEscape() -> Bool {
        switch mode {
            case .smart:
                if completion != nil {
                    dismissCompletion()
                    return true
                }
                guard !formula.isEmpty else { return false }
                endHistoryBrowsing()
                setFormula("")
                return true
            case .simple:
                guard !simple.expression.isEmpty || simple.error != nil else { return false }
                press(.clear)
                return true
            case .grid:
                return grid.handleEscape()
        }
    }
    
    // MARK: - Pasteboard
    
    /// The current result as plain text, if there is one.
    var currentResultText: String? {
        switch mode {
            case .smart:
                return calculation.value.map(FormulaFormatter.plain)
            case .simple:
                if simple.justEvaluated { return simple.expression }
                return simple.preview.value.map(FormulaFormatter.plain)
            case .grid:
                let text = grid.sheet.plainText(at: grid.activeCell)
                return text.isEmpty ? nil : text
        }
    }
    
    /// ⌘C: copies the result, unless text is selected in the editor (then the
    /// normal copy should happen). Returns whether it copied.
    func copyResultForShortcut() -> Bool {
        if mode == .smart, editorSelection.length > 0 { return false }
        return copyResult()
    }
    
    @discardableResult
    func copyResult() -> Bool {
        guard let text = currentResultText else { return false }
        copy(text)
        return true
    }
    
    func copyResult(of record: CalculationRecord) {
        copy(record.plainResult)
    }
    
    func copyExpression(of record: CalculationRecord) {
        copy(record.input)
    }
    
    func copyExpression() {
        guard case .value(_, let expression) = calculation else { return }
        copy(expression)
    }
    
    /// ⌘V on the keypad: takes a number or simple expression from the clipboard.
    func pasteIntoSimple() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), simple.load(text) else {
            NSSound.beep()
            return true
        }
        endHistoryBrowsing()
        return true
    }
    
    /// Puts `text` on the pasteboard and shows the "Copied" toast.
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedText = text
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: "Copied \(text)", .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.copiedText = nil
        }
    }
}
