//
//  GridModel.swift
//  Mini Khmer Dictionary
//

import AppKit
import Combine

/// The Grid mode: its sheets, the selection, whether a cell is being edited,
/// and the formula bar's help. Sheets and selection are plain values
/// (`Workbook`, `GridSelection`); this class adds the behaviour around them.
///
/// Two states, like any spreadsheet. Navigating: click, drag and arrows
/// select; typing or F2 starts an edit. Editing: the formula bar has the
/// keyboard, and a formula waiting for a value takes clicked or dragged cells
/// as references without leaving the edit.
@MainActor
final class GridModel: ObservableObject {
    @Published private(set) var workbook = Workbook()
    @Published private(set) var selection = GridSelection()
    @Published private(set) var isEditing = false
    /// The formula bar's text while editing.
    @Published private(set) var editText = ""

    @Published private(set) var completion: FormulaCompletion?
    @Published var completionIndex = 0
    @Published private(set) var signature: FormulaSignatureHint?
    /// What the formula being typed works out to right now.
    @Published private(set) var editPreview: FormulaCalculation = .empty

    @Published private(set) var caretRequest = CaretRequest()
    @Published private(set) var focusRequest = 0
    @Published private(set) var blurRequest = 0

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// The sheet tab showing a rename field.
    @Published private(set) var renamingSheet: Int?
    /// What ⌘C or ⌘X last took, shown with a moving dashed border until it is
    /// pasted (after a cut), Escape is pressed, or the sheet is edited.
    @Published private(set) var clipboard: GridClipboard?
    /// Where a drag of the fill handle would fill, shown as a dashed outline
    /// until the button comes up.
    @Published private(set) var fillTarget: CellRange?
    /// What each cell being filled would show, so the drag previews its
    /// result: 3, 4, 5 … or copies.
    @Published private(set) var fillPreview: [CellAddress: FormulaCalculation] = [:]
    /// The value the fill would end on, for the label beside the drag.
    @Published private(set) var fillEndText: String?

    let functions = FormulaFunctionRegistry.standard
    /// Puts text on the pasteboard and shows the "Copied" toast.
    var copyHandler: ((String) -> Void)?

    private var editorSelection = NSRange(location: 0, length: 0)
    private var completionDismissed = false
    /// The reference that clicking or dragging last put in the formula. The
    /// next click or drag replaces it, until the user types again.
    private var pointRange: NSRange?
    private var pointer: Pointer?
    private var undoStack: [Workbook] = []
    private var redoStack: [Workbook] = []
    private static let undoLimit = 50

    /// What a press on the cells is doing until the button comes up.
    private enum Pointer {
        case selecting(last: CellAddress)
        case pointing(origin: CellAddress, last: CellAddress)
    }

    // MARK: - Reading

    var sheet: Spreadsheet { workbook.active }
    var activeCell: CellAddress { selection.active }
    var size: (columns: Int, rows: Int) { (sheet.columns, sheet.rows) }

    /// What the formula bar shows: the edit in progress, or the active cell's
    /// input.
    var formulaBarText: String {
        isEditing ? editText : sheet.input(at: activeCell)
    }

    var selectedResult: FormulaCalculation {
        sheet.result(at: activeCell)
    }

    /// `B2`, or `B2:D5` for a single range.
    var nameBoxText: String {
        selection.ranges.count == 1 ? selection.current.name : activeCell.name
    }

    /// Sum, average and count of a multi-cell selection, like a spreadsheet's
    /// status bar. `nil` for a single cell.
    var selectionSummary: (cells: Int, numbers: Int, sum: Double, average: Double?)? {
        guard !selection.isSingleCell else { return nil }
        let cells = selection.cells
        let numbers: [Double] = cells.compactMap { cell in
            switch sheet.result(at: cell).value {
            case .number(let value)?, .percent(let value)?: value
            default: nil
            }
        }
        let filled = cells.filter { !sheet.input(at: $0).isEmpty }.count
        let sum = numbers.reduce(0, +)
        return (filled, numbers.count, sum, numbers.isEmpty ? nil : sum / Double(numbers.count))
    }

    /// Cells the formula in the bar refers to, tinted so you can see what it
    /// reads.
    var referencedCells: Set<CellAddress> {
        let text = formulaBarText
        guard Spreadsheet.isFormula(text) else { return [] }
        let tokens = FormulaLexer.tokenize(text)
        var cells: Set<CellAddress> = []
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            guard case .identifier(let name) = tokens[index].kind, let start = CellAddress(name) else { continue }
            if index + 2 < tokens.count, case .colon = tokens[index + 1].kind,
               case .identifier(let endName) = tokens[index + 2].kind, let end = CellAddress(endName) {
                if sheet.contains(start) {
                    cells.formUnion(CellRange(start, GridSelection.clamp(end, within: size)).cells)
                }
                index += 2
            } else if sheet.contains(start) {
                cells.insert(start)
            }
        }
        return cells
    }

    // MARK: - Selection

    func select(_ cell: CellAddress) {
        if isEditing { commit() }
        selection.select(GridSelection.clamp(cell, within: size))
    }

    /// Arrow, Tab or Return: moves the active cell and collapses the
    /// selection.
    func move(columns: Int = 0, rows: Int = 0) {
        if isEditing { commit() }
        selection.move(columns: columns, rows: rows, within: size)
    }

    /// Shift+arrow.
    func extendSelection(columns: Int = 0, rows: Int = 0) {
        selection.extend(columns: columns, rows: rows, within: size)
    }

    // MARK: - Pointer

    var isPointerDown: Bool { pointer != nil }

    /// The mouse went down on `cell`.
    ///
    /// - Editing a formula that's waiting for a value (after `=`, `(`, `,`, an
    ///   operator, or a reference just inserted this way): the cell's name goes
    ///   into the formula and the edit carries on. ⌘ keeps the last reference
    ///   and adds another after a comma.
    /// - Otherwise any edit is entered, and the click selects: Shift stretches
    ///   the selection, ⌘ adds a range, a double-click edits.
    func pointerDown(at cell: CellAddress, shift: Bool, command: Bool, clickCount: Int) {
        let cell = GridSelection.clamp(cell, within: size)

        if isEditing, Spreadsheet.isFormula(editText) {
            if command, pointRange != nil {
                appendArgumentSeparator()
            }
            if pointRange != nil || wantsReference {
                pointer = .pointing(origin: cell, last: cell)
                insertPointReference(cell.name)
                return
            }
        }
        if isEditing { commit() }

        if clickCount >= 2 {
            selection.select(cell)
            beginEditing()
            return
        }
        if shift {
            selection.extend(to: cell)
        } else if command {
            selection.add(cell)
        } else {
            selection.select(cell)
        }
        pointer = .selecting(last: cell)
    }

    /// The mouse, still down, is over `cell`.
    func pointerDragged(to cell: CellAddress) {
        let cell = GridSelection.clamp(cell, within: size)
        switch pointer {
        case .selecting(let last) where last != cell:
            selection.extend(to: cell)
            pointer = .selecting(last: cell)
        case .pointing(let origin, let last) where last != cell:
            insertPointReference(CellRange(origin, cell).name)
            pointer = .pointing(origin: origin, last: cell)
        default:
            break
        }
    }

    func pointerUp() {
        pointer = nil
    }

    /// Whether the caret sits where a value belongs.
    private var wantsReference: Bool {
        let source = editText as NSString
        guard Spreadsheet.isFormula(editText), editorSelection.location <= source.length else { return false }
        let before = source.substring(to: editorSelection.location)
        guard let last = before.trimmingCharacters(in: .whitespaces).last else { return false }
        return "=(,;:+-*/^&<>−×÷≠≤≥".contains(last)
    }

    /// Puts `name` at the caret, or over the reference the last click put in.
    private func insertPointReference(_ name: String) {
        let source = editText as NSString
        let target = (pointRange ?? editorSelection).clamped(toLength: source.length)
        let replaced = source.replacingCharacters(in: target, with: name)
        let length = (name as NSString).length
        setEditText(replaced, caret: target.location + length)
        pointRange = NSRange(location: target.location, length: length)
        focusRequest += 1
    }

    /// ⌘-click while pointing: keep the last reference and start another.
    private func appendArgumentSeparator() {
        guard let range = pointRange else { return }
        let source = editText as NSString
        let end = min(NSMaxRange(range), source.length)
        pointRange = nil
        setEditText(source.replacingCharacters(in: NSRange(location: end, length: 0), with: ", "), caret: end + 2)
    }

    // MARK: - Editing

    /// Starts editing the active cell, replacing its input with `initial`
    /// when typing began the edit, or keeping it for F2 and double-click.
    func beginEditing(with initial: String? = nil) {
        isEditing = true
        completionDismissed = false
        pointRange = nil
        setEditText(initial ?? sheet.input(at: activeCell), caret: nil)
        focusRequest += 1
    }

    /// The formula bar reports the user's own edits and caret moves here. A
    /// click into it while navigating starts an edit of the active cell.
    func editorDidChange(text: String, selection range: NSRange) {
        if !isEditing {
            isEditing = true
            completionDismissed = false
        }
        // Typing, or putting the caret elsewhere, ends "pointing": the next
        // click adds a reference rather than replacing this one.
        if let point = pointRange, text != editText || range != NSRange(location: NSMaxRange(point), length: 0) {
            pointRange = nil
        }
        editorSelection = range
        if text != editText {
            editText = text
            completionDismissed = false
        }
        updateAssistance()
    }

    /// Enter: the edit goes into the active cell, on every grouped sheet.
    func commit() {
        guard isEditing else { return }
        let before = workbook
        if workbook.setInput(editText, at: activeCell) {
            recordUndo(before)
            clipboard = nil
        }
        endEditing()
    }

    func cancelEditing() {
        guard isEditing else { return }
        endEditing()
    }

    private func endEditing() {
        isEditing = false
        editText = ""
        completion = nil
        signature = nil
        editPreview = .empty
        pointRange = nil
        pointer = nil
        blurRequest += 1
    }

    /// Return, Tab and the arrows from the formula bar.
    func handle(_ command: FormulaEditorCommand) -> Bool {
        switch command {
        case .commit:
            if completion != nil { acceptCompletion(); return true }
            move(rows: 1)
        case .complete:
            if completion != nil { acceptCompletion(); return true }
            move(columns: 1)
        case .backtab:
            move(columns: -1)
        case .moveUp:
            if let completion {
                completionIndex = (completionIndex - 1 + completion.names.count) % completion.names.count
                return true
            }
            move(rows: -1)
        case .moveDown:
            if let completion {
                completionIndex = (completionIndex + 1) % completion.names.count
                return true
            }
            move(rows: 1)
        }
        return true
    }

    func acceptCompletion(_ chosen: String? = nil) {
        guard let completion else { return }
        let name = chosen ?? completion.names[min(completionIndex, completion.names.count - 1)]
        let result = FormulaAssistant.accept(name, from: completion, in: editText, registry: functions)
        pointRange = nil
        setEditText(result.text, caret: result.caret)
        focusRequest += 1
    }

    /// Escape backs out one step: suggestions, a rename, the edit, then a
    /// multi-cell selection. Returns false when there was nothing left, so
    /// the popover can close.
    func handleEscape() -> Bool {
        if completion != nil {
            completionDismissed = true
            completion = nil
            return true
        }
        if renamingSheet != nil {
            renamingSheet = nil
            return true
        }
        if isEditing {
            cancelEditing()
            return true
        }
        if clipboard != nil {
            clipboard = nil
            return true
        }
        return selection.collapse()
    }

    private func setEditText(_ text: String, caret: Int?) {
        editText = text
        let location = caret ?? (text as NSString).length
        editorSelection = NSRange(location: location, length: 0)
        caretRequest = CaretRequest(id: caretRequest.id + 1, location: location)
        updateAssistance()
    }

    private func updateAssistance() {
        guard isEditing, Spreadsheet.isFormula(editText) else {
            completion = nil
            signature = nil
            editPreview = .empty
            return
        }
        let caret = editorSelection.location
        let found = (editorSelection.length == 0 && !completionDismissed)
            ? FormulaAssistant.completion(in: editText, caret: caret, registry: functions)
            : nil
        if found?.names != completion?.names { completionIndex = 0 }
        completion = found
        signature = FormulaAssistant.signature(in: editText, caret: caret, registry: functions)
        editPreview = FormulaAssistant.presenting(sheet.preview(editText, at: activeCell), completion: found)
    }

    // MARK: - Cell commands

    /// Delete: empties every selected cell (on every grouped sheet).
    func clearSelection() {
        let before = workbook
        if workbook.clear(selection.cells) {
            recordUndo(before)
            clipboard = nil
        }
    }

    func clearAll() {
        cancelEditing()
        let before = workbook
        if workbook.clearAll() {
            recordUndo(before)
            clipboard = nil
        }
    }

    // MARK: - Fill handle

    /// The fill handle is dragged over `cell`, with ⌥ held or not: works out
    /// what the fill would write, for the preview.
    func fillDragged(to cell: CellAddress, series: Bool = false) {
        if isEditing { commit() }
        let cell = GridSelection.clamp(cell, within: size)
        let source = selection.current
        guard let target = GridFill.target(from: source, to: cell) else {
            clearFillPreview()
            return
        }
        fillTarget = target
        let changes = GridFill.fill(source, into: target, in: sheet, series: series)
        var preview = sheet
        preview.setInputs(changes)
        fillPreview = Dictionary(uniqueKeysWithValues: changes.keys.map { ($0, preview.result(at: $0)) })

        // The far end of the drag, where the label sits.
        let end = CellAddress(
            column: target.bottomRight.column > source.bottomRight.column ? target.bottomRight.column : target.topLeft.column,
            row: target.bottomRight.row > source.bottomRight.row ? target.bottomRight.row : target.topLeft.row
        )
        let far = source.contains(end) ? target.bottomRight : end
        fillEndText = preview.result(at: far).value.map { FormulaFormatter.display($0) }
    }

    private func clearFillPreview() {
        fillTarget = nil
        fillPreview = [:]
        fillEndText = nil
    }

    /// The fill handle is let go: fills the cells dragged over and selects
    /// the whole filled range. ⌥ makes a single number count up.
    func fillEnded(series: Bool) {
        defer { clearFillPreview() }
        guard let target = fillTarget, selection.ranges.count == 1 else { return }
        let before = workbook
        if workbook.fill(selection.current, into: target, series: series) {
            recordUndo(before)
            clipboard = nil
        }
        selection.select(target.topLeft, to: target.bottomRight)
    }

    // MARK: - Copy and paste

    /// The copied range on the sheet showing now, for the dashed border.
    var copiedRange: CellRange? {
        guard let clipboard, clipboard.sheetIndex == workbook.activeIndex else { return nil }
        return clipboard.range
    }

    /// The clipboard, while the pasteboard still holds what it put there. Once
    /// something else is copied — here or in another app — a paste takes that.
    private var liveClipboard: GridClipboard? {
        guard let clipboard, clipboard.changeCount == NSPasteboard.general.changeCount else { return nil }
        return clipboard
    }

    var canPaste: Bool {
        liveClipboard != nil || NSPasteboard.general.string(forType: .string)?.isEmpty == false
    }

    /// ⌘C: puts the values on the pasteboard — one cell's value, or tab-
    /// separated rows that paste into Numbers or Excel — and remembers the
    /// formulas, so a paste here keeps them. The range gets a moving border.
    func copySelection() {
        takeSelection(cut: false)
    }

    /// ⌘X: like copy, but the cells move when pasted. Nothing changes until
    /// then, and Escape cancels, as in a spreadsheet.
    func cutSelection() {
        takeSelection(cut: true)
    }

    private func takeSelection(cut: Bool) {
        if isEditing { commit() }
        let selected = selection
        guard selected.cells.contains(where: { !sheet.input(at: $0).isEmpty }) else {
            NSSound.beep()
            return
        }
        let range = selected.bounds
        let index = workbook.activeIndex
        let values = workbook.values(in: range, onSheet: index, selected: selected.contains)
        let text = selected.isSingleCell
            ? sheet.plainText(at: activeCell)
            : values.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        copyHandler?(text)
        clipboard = GridClipboard(
            sheetIndex: index,
            range: range,
            inputs: workbook.inputs(in: range, onSheet: index, selected: selected.contains),
            values: values,
            isCut: cut,
            changeCount: NSPasteboard.general.changeCount
        )
    }

    enum PasteKind {
        /// Formulas with their references moved, from a copy made here;
        /// otherwise whatever text is on the pasteboard.
        case normal
        /// Only what the cells showed — numbers and text, no formulas.
        case values
    }

    /// ⌘V (`.normal`) and ⇧⌘V (`.values`). Pastes at the top-left of the
    /// selection; the pasted block becomes the selection. A single copied
    /// cell pasted over a range fills the whole range.
    func paste(_ kind: PasteKind = .normal) {
        if isEditing { commit() }
        let origin = selection.current.topLeft
        let before = workbook
        var written: [CellAddress]

        if let copied = liveClipboard {
            let target = selection.current
            let fill = copied.range.isSingleCell && !target.isSingleCell
            let block: [[String]]
            if fill {
                block = (0..<target.rowCount).map { row in
                    (0..<target.columnCount).map { column in
                        kind == .values ? copied.values[0][0]
                            : Self.moved(copied.inputs[0][0], from: copied.range.topLeft,
                                         to: CellAddress(column: origin.column + column, row: origin.row + row))
                    }
                }
            } else if kind == .values {
                block = copied.values
            } else {
                block = copied.inputs.enumerated().map { row, inputs in
                    inputs.enumerated().map { column, input in
                        Self.moved(input, from: copied.range.topLeft,
                                   to: CellAddress(column: origin.column + column, row: origin.row + row))
                    }
                }
            }
            if copied.isCut {
                // The source empties first, so a move onto an overlapping
                // range keeps what was just written.
                workbook.clear(copied.range.cells, onSheet: copied.sheetIndex)
                clipboard = nil
            }
            written = workbook.setBlock(block, at: origin)
        } else {
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
                NSSound.beep()
                return
            }
            // From another app the text is values already; keep a formula
            // only if it was typed as one and pasting values wasn't asked.
            let pasted = kind == .values && Spreadsheet.isFormula(text) ? "'" + text : text
            written = workbook.paste(pasted, at: origin)
        }

        if workbook != before { recordUndo(before) }
        if written.count > 1 {
            let corner = CellAddress(column: written.map(\.column).max()!, row: written.map(\.row).max()!)
            selection.select(origin, to: corner)
        }
    }

    private static func moved(_ input: String, from source: CellAddress, to target: CellAddress) -> String {
        Spreadsheet.shiftingReferences(in: input, columns: target.column - source.column, rows: target.row - source.row)
    }

    /// A context-menu command on `cell` acts on the selection when the cell is
    /// part of it, and on that cell alone otherwise — what right-clicking a
    /// cell does in a spreadsheet.
    func prepareContextAction(at cell: CellAddress) {
        if isEditing { commit() }
        if !selection.contains(cell) { selection.select(cell) }
    }

    // MARK: - Sheets

    /// A click on a sheet tab: plain shows it alone, Shift groups the run up
    /// to it, ⌘ adds or removes it from the group, double-click renames.
    func clickSheet(_ index: Int, shift: Bool, command: Bool, clickCount: Int) {
        if isEditing { commit() }
        renamingSheet = nil
        if shift {
            workbook.groupThrough(index)
        } else if command {
            workbook.toggleGroup(index)
        } else {
            workbook.activate(index)
            if clickCount >= 2 { renamingSheet = index }
        }
    }

    func addSheet() {
        if isEditing { commit() }
        let before = workbook
        if workbook.addSheet() != nil { recordUndo(before) }
        renamingSheet = nil
    }

    func deleteSheet(_ index: Int) {
        cancelEditing()
        let before = workbook
        workbook.deleteSheet(index)
        if workbook != before { recordUndo(before) }
        renamingSheet = nil
    }

    func beginRenaming(_ index: Int) {
        if isEditing { commit() }
        renamingSheet = index
    }

    func renameSheet(_ index: Int, to name: String) {
        let before = workbook
        if workbook.renameSheet(index, to: name), workbook != before { recordUndo(before) }
        renamingSheet = nil
    }

    func cancelRenaming() {
        renamingSheet = nil
    }

    // MARK: - Undo

    private func recordUndo(_ before: Workbook) {
        undoStack.append(before)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        updateUndoState()
    }

    func undo() {
        cancelEditing()
        clipboard = nil
        guard let previous = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append(workbook)
        workbook = previous
        updateUndoState()
    }

    func redo() {
        cancelEditing()
        clipboard = nil
        guard let next = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append(workbook)
        workbook = next
        updateUndoState()
    }

    private func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}

/// A copied or cut range: its formulas, for pasting here, and its values,
/// which are also what went on the pasteboard for other apps.
struct GridClipboard: Equatable {
    let sheetIndex: Int
    let range: CellRange
    let inputs: [[String]]
    let values: [[String]]
    let isCut: Bool
    /// The pasteboard's change count right after copying. When it moves on,
    /// something else was copied and this is stale.
    let changeCount: Int
}
