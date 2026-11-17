//
//  Workbook.swift
//  Mini Khmer Dictionary
//
//  Foundation only; tested by Tools/test_formula_engine.sh.
//

import Foundation

/// A named sheet of cells.
struct GridSheet: Equatable {
    var name: String
    var cells: Spreadsheet
}

/// The Grid's sheets, which one is showing, and which are grouped.
///
/// Grouping works as in a spreadsheet: Shift-click or ⌘-click more sheet
/// tabs, and whatever is typed, cleared or pasted lands at the same cells on
/// every grouped sheet — handy for months or branches laid out alike.
struct Workbook: Equatable {
    static let maximumSheets = 12
    static let maximumNameLength = 31

    private(set) var sheets: [GridSheet]
    private(set) var activeIndex = 0
    /// Always holds `activeIndex`.
    private(set) var groupedIndices: Set<Int> = [0]

    init(columns: Int = 6, rows: Int = 30) {
        sheets = [GridSheet(name: "Sheet 1", cells: Spreadsheet(columns: columns, rows: rows))]
    }

    var active: Spreadsheet { sheets[activeIndex].cells }
    var isGrouped: Bool { groupedIndices.count > 1 }
    var canAddSheet: Bool { sheets.count < Self.maximumSheets }
    var canDeleteSheet: Bool { sheets.count > 1 }

    // MARK: - Tabs

    /// A plain click: show this sheet on its own.
    mutating func activate(_ index: Int) {
        guard sheets.indices.contains(index) else { return }
        activeIndex = index
        groupedIndices = [index]
    }

    /// Shift-click: group every sheet from the active one to `index`.
    mutating func groupThrough(_ index: Int) {
        guard sheets.indices.contains(index) else { return }
        groupedIndices = Set(min(activeIndex, index)...max(activeIndex, index))
    }

    /// ⌘-click: add or remove one sheet from the group. The active sheet
    /// stays in it.
    mutating func toggleGroup(_ index: Int) {
        guard sheets.indices.contains(index), index != activeIndex else { return }
        if groupedIndices.contains(index) {
            groupedIndices.remove(index)
        } else {
            groupedIndices.insert(index)
        }
    }

    /// Adds an empty sheet after the others and shows it. Returns its index.
    @discardableResult
    mutating func addSheet() -> Int? {
        guard canAddSheet else { return nil }
        let template = active
        sheets.append(GridSheet(name: nextSheetName(), cells: Spreadsheet(columns: template.columns, rows: template.rows)))
        activate(sheets.count - 1)
        return sheets.count - 1
    }

    mutating func deleteSheet(_ index: Int) {
        guard canDeleteSheet, sheets.indices.contains(index) else { return }
        sheets.remove(at: index)
        let showing = index < activeIndex ? activeIndex - 1 : min(activeIndex, sheets.count - 1)
        activate(showing)
    }

    /// Renames a sheet. Refuses empty names and names another sheet has.
    @discardableResult
    mutating func renameSheet(_ index: Int, to name: String) -> Bool {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumNameLength))
        guard sheets.indices.contains(index), !trimmed.isEmpty else { return false }
        let taken = sheets.indices.contains { $0 != index && sheets[$0].name.caseInsensitiveCompare(trimmed) == .orderedSame }
        guard !taken else { return false }
        sheets[index].name = trimmed
        return true
    }

    private func nextSheetName() -> String {
        var number = sheets.count + 1
        while sheets.contains(where: { $0.name.caseInsensitiveCompare("Sheet \(number)") == .orderedSame }) {
            number += 1
        }
        return "Sheet \(number)"
    }

    // MARK: - Editing the grouped sheets

    /// Enters `text` at `cell` on every grouped sheet. Returns whether
    /// anything changed.
    @discardableResult
    mutating func setInput(_ text: String, at cell: CellAddress) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return applyToGroup { sheet in
            guard sheet.input(at: cell) != trimmed else { return false }
            sheet.setInputs([cell: trimmed])
            return true
        }
    }

    /// Empties `cells` on every grouped sheet.
    @discardableResult
    mutating func clear(_ cells: [CellAddress]) -> Bool {
        applyToGroup { sheet in
            let filled = cells.filter { !sheet.input(at: $0).isEmpty }
            guard !filled.isEmpty else { return false }
            sheet.setInputs(Dictionary(uniqueKeysWithValues: filled.map { ($0, "") }))
            return true
        }
    }

    @discardableResult
    mutating func clearAll() -> Bool {
        applyToGroup { sheet in
            guard !sheet.isEmpty else { return false }
            sheet.clearAll()
            return true
        }
    }

    /// Pastes tab-separated text at `origin` on every grouped sheet. Returns
    /// the cells written on the active sheet.
    @discardableResult
    mutating func paste(_ text: String, at origin: CellAddress) -> [CellAddress] {
        var written: [CellAddress] = []
        for index in groupedIndices.sorted() {
            let cells = sheets[index].cells.paste(text, at: origin)
            if index == activeIndex { written = cells }
        }
        return written
    }

    /// Writes a block of inputs (formulas kept as typed) at `origin` on every
    /// grouped sheet. Returns the cells written on the active sheet.
    mutating func setBlock(_ block: [[String]], at origin: CellAddress) -> [CellAddress] {
        var written: [CellAddress] = []
        for index in groupedIndices.sorted() {
            let cells = sheets[index].cells.setBlock(block, at: origin)
            if index == activeIndex { written = cells }
        }
        return written
    }

    /// Continues `source` into `target` on every grouped sheet, each from its
    /// own cells. See `GridFill`.
    @discardableResult
    mutating func fill(_ source: CellRange, into target: CellRange, series: Bool) -> Bool {
        applyToGroup { sheet in
            let changes = GridFill.fill(source, into: target, in: sheet, series: series)
                .filter { sheet.input(at: $0.key) != $0.value }
            guard !changes.isEmpty else { return false }
            sheet.setInputs(changes)
            return true
        }
    }

    /// The inputs of sheet `index` in `range`, row by row; cells outside
    /// `selected` come back empty.
    func inputs(in range: CellRange, onSheet index: Int, selected: (CellAddress) -> Bool = { _ in true }) -> [[String]] {
        let sheet = sheets[index].cells
        return (range.topLeft.row...range.bottomRight.row).map { row in
            (range.topLeft.column...range.bottomRight.column).map { column in
                let cell = CellAddress(column: column, row: row)
                return selected(cell) ? sheet.input(at: cell) : ""
            }
        }
    }

    /// The values of sheet `index` in `range`, row by row, as plain text.
    func values(in range: CellRange, onSheet index: Int, selected: (CellAddress) -> Bool = { _ in true }) -> [[String]] {
        let sheet = sheets[index].cells
        return (range.topLeft.row...range.bottomRight.row).map { row in
            (range.topLeft.column...range.bottomRight.column).map { column in
                let cell = CellAddress(column: column, row: row)
                return selected(cell) ? sheet.plainText(at: cell) : ""
            }
        }
    }

    /// Empties `cells` on sheet `index` only — the source of a cut, which
    /// stays where it was cut from even if another sheet is showing now.
    mutating func clear(_ cells: [CellAddress], onSheet index: Int) {
        guard sheets.indices.contains(index) else { return }
        let filled = cells.filter { !sheets[index].cells.input(at: $0).isEmpty }
        guard !filled.isEmpty else { return }
        sheets[index].cells.setInputs(Dictionary(uniqueKeysWithValues: filled.map { ($0, "") }))
    }

    private mutating func applyToGroup(_ change: (inout Spreadsheet) -> Bool) -> Bool {
        var changed = false
        for index in groupedIndices.sorted() {
            if change(&sheets[index].cells) { changed = true }
        }
        return changed
    }

    // MARK: - Copying

    /// The active sheet's values in `range` as tab-separated rows, the way
    /// Numbers and Excel paste them. Cells outside `selected` are left blank.
    func tabSeparatedValues(in range: CellRange, selected: (CellAddress) -> Bool = { _ in true }) -> String {
        (range.topLeft.row...range.bottomRight.row).map { row in
            (range.topLeft.column...range.bottomRight.column).map { column in
                let cell = CellAddress(column: column, row: row)
                return selected(cell) ? active.plainText(at: cell) : ""
            }.joined(separator: "\t")
        }.joined(separator: "\n")
    }
}
