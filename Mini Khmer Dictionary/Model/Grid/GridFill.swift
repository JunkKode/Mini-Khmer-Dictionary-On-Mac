//
//  GridFill.swift
//  Mini Khmer Dictionary
//
//  Foundation only; tested by Tools/test_formula_engine.sh.
//

import Foundation

/// Dragging the fill handle, the dot at a selection's corner: the selected
/// cells are continued into the cells dragged over, the way a spreadsheet
/// does it.
///
/// - Numbers that form a pattern continue it: 1, 2 → 3, 4; 10, 20 → 30. A
///   single number is copied, unless `series` is asked for (⌥-drag), when it
///   counts up by one.
/// - Text ending in a number counts on: Item 1 → Item 2, Item 3.
/// - Months and weekdays, in English or Khmer, carry on round the calendar.
/// - Formulas are copied with their references moved, as when pasting.
/// - Anything else, including several identical values, is repeated.
enum GridFill {
    /// The range the fill covers when the handle of `source` is dragged to
    /// `cell`: stretched along one axis only, whichever the pointer moved
    /// further along. `nil` while the pointer is still inside the source.
    static func target(from source: CellRange, to cell: CellAddress) -> CellRange? {
        let top = source.topLeft, bottom = source.bottomRight
        let down = cell.row - bottom.row, up = top.row - cell.row
        let right = cell.column - bottom.column, left = top.column - cell.column
        let vertical = max(down, up), horizontal = max(right, left)
        guard max(vertical, horizontal) > 0 else { return nil }
        if vertical >= horizontal {
            return down > 0
                ? CellRange(top, CellAddress(column: bottom.column, row: cell.row))
                : CellRange(CellAddress(column: top.column, row: cell.row), bottom)
        }
        return right > 0
            ? CellRange(top, CellAddress(column: cell.column, row: bottom.row))
            : CellRange(CellAddress(column: cell.column, row: top.row), bottom)
    }

    /// New inputs for the cells of `target` outside `source`, worked out from
    /// the inputs in `source`.
    static func fill(_ source: CellRange, into target: CellRange, in sheet: Spreadsheet, series: Bool = false) -> [CellAddress: String] {
        let vertical = target.columnCount == source.columnCount
            && (target.topLeft.row < source.topLeft.row || target.bottomRight.row > source.bottomRight.row)
        var changes: [CellAddress: String] = [:]

        // One line per column when filling down or up, per row when filling
        // across.
        let lines = vertical
            ? Array(source.topLeft.column...source.bottomRight.column)
            : Array(source.topLeft.row...source.bottomRight.row)
        for line in lines {
            let sourceCells: [CellAddress] = vertical
                ? (source.topLeft.row...source.bottomRight.row).map { CellAddress(column: line, row: $0) }
                : (source.topLeft.column...source.bottomRight.column).map { CellAddress(column: $0, row: line) }
            let targetCells: [CellAddress] = vertical
                ? (target.topLeft.row...target.bottomRight.row).map { CellAddress(column: line, row: $0) }
                : (target.topLeft.column...target.bottomRight.column).map { CellAddress(column: $0, row: line) }
            let inputs = sourceCells.map { sheet.input(at: $0) }
            let pattern = Pattern(inputs, series: series)
            let first = sourceCells[0]

            for cell in targetCells where !source.contains(cell) {
                // Position along the line relative to the first source cell;
                // negative when filling up or left.
                let index = vertical ? cell.row - first.row : cell.column - first.column
                let repeated = sourceCells[((index % inputs.count) + inputs.count) % inputs.count]
                changes[cell] = pattern.value(at: index, cell: cell, repeating: repeated, inputs: inputs, sourceCells: sourceCells)
            }
        }
        return changes
    }

    /// How one line of source cells continues.
    private enum Pattern {
        case linear(intercept: Double, slope: Double, percent: Bool)
        case numberedText(prefix: String, start: Int, step: Int, width: Int, khmer: Bool)
        case list([String], start: Int, step: Int)
        case repeat_

        init(_ inputs: [String], series: Bool) {
            // Numbers: a straight line through them (exact for 1, 2, 3 or 10,
            // 20), or a step of one from a single number when asked.
            let values = inputs.map(Spreadsheet.literal)
            let numbers: [Double] = values.compactMap {
                switch $0 {
                case .number(let value): value
                case .percent(let value): value
                default: nil
                }
            }
            if numbers.count == inputs.count, !inputs.contains(where: Spreadsheet.isFormula) {
                let percent = values.allSatisfy { if case .percent = $0 { true } else { false } }
                if numbers.count == 1 {
                    self = series ? .linear(intercept: numbers[0], slope: percent ? 0.01 : 1, percent: percent) : .repeat_
                    return
                }
                if Set(numbers).count == 1 && !series {
                    self = .repeat_
                    return
                }
                let n = Double(numbers.count)
                let meanX = (n - 1) / 2
                let meanY = numbers.reduce(0, +) / n
                var covariance = 0.0, variance = 0.0
                for (x, y) in numbers.enumerated() {
                    covariance += (Double(x) - meanX) * (y - meanY)
                    variance += (Double(x) - meanX) * (Double(x) - meanX)
                }
                let slope = covariance / variance
                self = .linear(intercept: meanY - slope * meanX, slope: slope, percent: percent)
                return
            }

            // Text ending in a whole number, all with the same text before it.
            let numbered = inputs.compactMap(Self.splitNumber)
            if numbered.count == inputs.count, Set(numbered.map(\.prefix)).count == 1 {
                let step = numbered.count > 1 ? numbered[1].number - numbered[0].number : 1
                self = .numberedText(prefix: numbered[0].prefix, start: numbered[0].number, step: step,
                                     width: numbered[0].width, khmer: numbered[0].khmer)
                return
            }

            // Months and weekdays.
            for list in Self.lists {
                let positions = inputs.compactMap { input in
                    list.firstIndex { $0.compare(input, options: .caseInsensitive) == .orderedSame }
                }
                if positions.count == inputs.count {
                    let step = positions.count > 1 ? positions[1] - positions[0] : 1
                    // Keep the case the user typed: JAN stays upper case.
                    let shown = inputs[0] == inputs[0].uppercased() && inputs[0] != inputs[0].lowercased()
                        ? list.map { $0.uppercased() } : list
                    self = .list(shown, start: positions[0], step: step)
                    return
                }
            }
            self = .repeat_
        }

        func value(at index: Int, cell: CellAddress, repeating source: CellAddress, inputs: [String], sourceCells: [CellAddress]) -> String {
            switch self {
            case .linear(let intercept, let slope, let percent):
                let value = intercept + slope * Double(index)
                // Rounded so 0.1 + 0.2-style drift doesn't show.
                let clean = (value * 1e9).rounded() / 1e9
                return percent ? FormulaFormatter.plain(clean * 100) + "%" : FormulaFormatter.plain(clean)
            case .numberedText(let prefix, let start, let step, let width, let khmer):
                let number = start + step * index
                var digits = String(abs(number))
                if digits.count < width { digits = String(repeating: "0", count: width - digits.count) + digits }
                return prefix + (number < 0 ? "-" : "") + (khmer ? KhmerNumbers.digits(digits) : digits)
            case .list(let names, let start, let step):
                let count = names.count
                return names[(((start + step * index) % count) + count) % count]
            case .repeat_:
                let input = inputs[sourceCells.firstIndex(of: source)!]
                return Spreadsheet.shiftingReferences(
                    in: input, columns: cell.column - source.column, rows: cell.row - source.row
                )
            }
        }

        /// `Item 12` → ("Item ", 12, 2); `ថ្ងៃទី១` → ("ថ្ងៃទី", 1, 1, Khmer
        /// digits). Numbers after a point or a minus aren't counted on.
        static func splitNumber(_ input: String) -> (prefix: String, number: Int, width: Int, khmer: Bool)? {
            guard !Spreadsheet.isFormula(input) else { return nil }
            let scalars = Array(input.unicodeScalars)
            let isDigit = { (scalar: Unicode.Scalar) in ("0"..."9").contains(scalar) || (0x17E0...0x17E9).contains(scalar.value) }
            var start = scalars.count
            while start > 0, isDigit(scalars[start - 1]) { start -= 1 }
            let count = scalars.count - start
            guard count > 0, start > 0, count <= 9 else { return nil }
            let last = scalars[start - 1]
            guard last != ".", last != "-", last != "," else { return nil }
            let digits = KhmerNumbers.westernDigits(String(String.UnicodeScalarView(scalars[start...])))
            guard let number = Int(digits) else { return nil }
            let prefix = String(String.UnicodeScalarView(scalars[..<start]))
            return (prefix, number, count, (0x17E0...0x17E9).contains(scalars[start].value))
        }

        static let lists: [[String]] = [
            ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"],
            ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
            ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
            ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
            ["មករា", "កុម្ភៈ", "មីនា", "មេសា", "ឧសភា", "មិថុនា", "កក្កដា", "សីហា", "កញ្ញា", "តុលា", "វិច្ឆិកា", "ធ្នូ"],
            ["ច័ន្ទ", "អង្គារ", "ពុធ", "ព្រហស្បតិ៍", "សុក្រ", "សៅរ៍", "អាទិត្យ"],
            ["ថ្ងៃច័ន្ទ", "ថ្ងៃអង្គារ", "ថ្ងៃពុធ", "ថ្ងៃព្រហស្បតិ៍", "ថ្ងៃសុក្រ", "ថ្ងៃសៅរ៍", "ថ្ងៃអាទិត្យ"],
        ]
    }
}
