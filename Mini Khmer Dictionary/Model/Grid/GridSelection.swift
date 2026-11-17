//
//  GridSelection.swift
//  Mini Khmer Dictionary
//
//  Foundation only; tested by Tools/test_formula_engine.sh.
//

import Foundation

/// A rectangle of cells from the cell where it started (`anchor`) to the one
/// the pointer or Shift+arrow has reached (`end`).
struct CellRange: Hashable {
    var anchor: CellAddress
    var end: CellAddress

    init(_ anchor: CellAddress, _ end: CellAddress? = nil) {
        self.anchor = anchor
        self.end = end ?? anchor
    }

    var topLeft: CellAddress {
        CellAddress(column: min(anchor.column, end.column), row: min(anchor.row, end.row))
    }

    var bottomRight: CellAddress {
        CellAddress(column: max(anchor.column, end.column), row: max(anchor.row, end.row))
    }

    var isSingleCell: Bool { anchor == end }

    var columnCount: Int { bottomRight.column - topLeft.column + 1 }
    var rowCount: Int { bottomRight.row - topLeft.row + 1 }

    func contains(_ cell: CellAddress) -> Bool {
        (topLeft.column...bottomRight.column).contains(cell.column)
            && (topLeft.row...bottomRight.row).contains(cell.row)
    }

    /// Row by row.
    var cells: [CellAddress] { CellAddress.range(topLeft, bottomRight) }

    /// `B2`, or `B2:D5` written top-left first however it was dragged.
    var name: String {
        isSingleCell ? anchor.name : "\(topLeft.name):\(bottomRight.name)"
    }
}

/// The Grid's selection: one or more ranges and the active cell, the one the
/// formula bar edits. Like a spreadsheet:
///
/// - click selects one cell; drag or Shift+click/arrow stretches the newest
///   range from where it started;
/// - ⌘-click starts another range alongside the others.
struct GridSelection: Equatable {
    /// Never empty. The last one is the one that stretches.
    private(set) var ranges: [CellRange]
    private(set) var active: CellAddress

    init(_ cell: CellAddress = CellAddress(column: 0, row: 0)) {
        ranges = [CellRange(cell)]
        active = cell
    }

    var current: CellRange { ranges[ranges.count - 1] }

    var isSingleCell: Bool { ranges.count == 1 && ranges[0].isSingleCell }

    func contains(_ cell: CellAddress) -> Bool {
        ranges.contains { $0.contains(cell) }
    }

    /// Every selected cell once, row by row.
    var cells: [CellAddress] {
        Array(Set(ranges.flatMap(\.cells))).sorted()
    }

    /// The smallest rectangle holding every range.
    var bounds: CellRange {
        let corners = ranges.flatMap { [$0.topLeft, $0.bottomRight] }
        return CellRange(
            CellAddress(column: corners.map(\.column).min()!, row: corners.map(\.row).min()!),
            CellAddress(column: corners.map(\.column).max()!, row: corners.map(\.row).max()!)
        )
    }

    var columns: Set<Int> {
        Set(ranges.flatMap { $0.topLeft.column...$0.bottomRight.column })
    }

    var rows: Set<Int> {
        Set(ranges.flatMap { $0.topLeft.row...$0.bottomRight.row })
    }

    /// Which sides of `cell` sit on the outline of the selection.
    func outline(of cell: CellAddress) -> (top: Bool, left: Bool, bottom: Bool, right: Bool) {
        guard contains(cell) else { return (false, false, false, false) }
        return (
            !contains(CellAddress(column: cell.column, row: cell.row - 1)),
            !contains(CellAddress(column: cell.column - 1, row: cell.row)),
            !contains(CellAddress(column: cell.column, row: cell.row + 1)),
            !contains(CellAddress(column: cell.column + 1, row: cell.row))
        )
    }

    // MARK: - Changing

    /// Just this cell.
    mutating func select(_ cell: CellAddress) {
        ranges = [CellRange(cell)]
        active = cell
    }

    /// Range from `start` to `end` with `start` active, e.g. after a paste.
    mutating func select(_ start: CellAddress, to end: CellAddress) {
        ranges = [CellRange(start, end)]
        active = start
    }

    /// Stretches the newest range to `cell`; the active cell stays put.
    mutating func extend(to cell: CellAddress) {
        ranges[ranges.count - 1].end = cell
    }

    /// Starts another range at `cell` (⌘-click).
    mutating func add(_ cell: CellAddress) {
        ranges.append(CellRange(cell))
        active = cell
    }

    /// Back to just the active cell. Returns false if it already was.
    mutating func collapse() -> Bool {
        guard !isSingleCell else { return false }
        select(active)
        return true
    }

    /// An arrow key: the active cell moves and the selection collapses to it.
    mutating func move(columns: Int, rows: Int, within size: (columns: Int, rows: Int)) {
        select(Self.clamp(CellAddress(column: active.column + columns, row: active.row + rows), within: size))
    }

    /// Shift+arrow: the far corner of the newest range moves.
    mutating func extend(columns: Int, rows: Int, within size: (columns: Int, rows: Int)) {
        let end = current.end
        extend(to: Self.clamp(CellAddress(column: end.column + columns, row: end.row + rows), within: size))
    }

    static func clamp(_ cell: CellAddress, within size: (columns: Int, rows: Int)) -> CellAddress {
        CellAddress(
            column: min(max(cell.column, 0), size.columns - 1),
            row: min(max(cell.row, 0), size.rows - 1)
        )
    }
}
