//
//  FormulaCells.swift
//  Mini Khmer Dictionary
//

import Foundation

/// A cell such as `B12`. Zero-based internally: `B12` is column 1, row 11.
struct CellAddress: Hashable, Comparable {
    let column: Int
    let row: Int

    init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    /// Parses `A1`, `b12`, `AA100`: one or two letters, then a row from 1.
    init?(_ name: String) {
        let units = Array(name.uppercased().unicodeScalars)
        var index = 0
        var column = 0
        while index < units.count, index < 2, ("A"..."Z").contains(units[index]) {
            column = column * 26 + Int(units[index].value - 64)
            index += 1
        }
        let digits = units[index...]
        guard index > 0, !digits.isEmpty, digits.count <= 4,
              digits.first != "0",
              digits.allSatisfy({ ("0"..."9").contains($0) }),
              let row = Int(String(String.UnicodeScalarView(digits))) else { return nil }
        self.column = column - 1
        self.row = row - 1
    }

    /// `B12`.
    var name: String { Self.columnName(column) + String(row + 1) }

    /// `A`, `B`, … `Z`, `AA`, …
    static func columnName(_ index: Int) -> String {
        var index = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + index % 26))) + name
            index = index / 26 - 1
        } while index >= 0
        return name
    }

    static func < (lhs: CellAddress, rhs: CellAddress) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }

    /// Every cell in the rectangle between two corners, row by row.
    static func range(_ a: CellAddress, _ b: CellAddress) -> [CellAddress] {
        let rows = min(a.row, b.row)...max(a.row, b.row)
        let columns = min(a.column, b.column)...max(a.column, b.column)
        return rows.flatMap { row in columns.map { CellAddress(column: $0, row: row) } }
    }
}

/// Lets formulas read cells, e.g. from the Grid. Without one, `A1` in a
/// formula is an error.
struct FormulaCells {
    let columns: Int
    let rows: Int
    /// The value in a cell, `nil` when it's empty. Throws the cell's own error.
    let value: (CellAddress) throws -> FormulaValue?

    func contains(_ address: CellAddress) -> Bool {
        (0..<columns).contains(address.column) && (0..<rows).contains(address.row)
    }

    /// `A1:F30`, for messages.
    var extent: String {
        "A1:" + CellAddress(column: columns - 1, row: rows - 1).name
    }
}
