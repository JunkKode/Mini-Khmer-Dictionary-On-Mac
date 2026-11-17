//
//  Spreadsheet.swift
//  Mini Khmer Dictionary
//
//  Foundation only, like the formula engine, so it is tested alongside it by
//  Tools/test_formula_engine.sh.
//

import Foundation

/// The Grid's cells: what was typed in each, and what each works out to.
///
/// Every edit recalculates the whole sheet. At a few hundred cells that takes
/// microseconds, and it means there is no dependency graph to keep in sync.
struct Spreadsheet: Equatable {
    let columns: Int
    let rows: Int

    /// Exactly what was typed, keyed by cell. Empty cells have no entry.
    private(set) var inputs: [CellAddress: String] = [:]
    /// What each filled cell shows: a value or an error.
    private(set) var results: [CellAddress: FormulaCalculation] = [:]

    var engine = FormulaEngine()

    init(columns: Int = 6, rows: Int = 30) {
        self.columns = columns
        self.rows = rows
    }

    static func == (lhs: Spreadsheet, rhs: Spreadsheet) -> Bool {
        lhs.columns == rhs.columns && lhs.rows == rhs.rows && lhs.inputs == rhs.inputs
    }

    var isEmpty: Bool { inputs.isEmpty }

    func contains(_ address: CellAddress) -> Bool {
        (0..<columns).contains(address.column) && (0..<rows).contains(address.row)
    }

    func input(at address: CellAddress) -> String {
        inputs[address] ?? ""
    }

    func result(at address: CellAddress) -> FormulaCalculation {
        results[address] ?? .empty
    }

    func isFormula(at address: CellAddress) -> Bool {
        Self.isFormula(input(at: address))
    }

    /// The cell's value as plain text, for copying: `1234.5`, `15%`, `#DIV/0!`.
    func plainText(at address: CellAddress) -> String {
        switch result(at: address) {
        case .empty: ""
        case .value(let value, _): FormulaFormatter.plain(value)
        case .failure(let error): error.code
        }
    }

    /// What `input` would show if it were entered at `address`, for a live
    /// preview while typing. Nothing is changed.
    func preview(_ input: String, at address: CellAddress) -> FormulaCalculation {
        var copy = self
        copy.setInput(input, at: address)
        return copy.result(at: address)
    }

    // MARK: - Editing

    mutating func setInput(_ text: String, at address: CellAddress) {
        setInputs([address: text])
    }

    /// Several cells at once, recalculating once. An empty string clears.
    mutating func setInputs(_ changes: [CellAddress: String]) {
        for (address, text) in changes where contains(address) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            inputs[address] = trimmed.isEmpty ? nil : trimmed
        }
        recalculate()
    }

    mutating func clearAll() {
        inputs.removeAll()
        recalculate()
    }

    /// Replaces every input at once, e.g. to undo.
    mutating func restore(_ inputs: [CellAddress: String]) {
        self.inputs = inputs.filter { contains($0.key) }
        recalculate()
    }

    /// Pastes tab-separated rows (what Numbers and Excel copy) with `origin`
    /// as the top-left corner. Cells beyond the grid are dropped. Returns the
    /// cells written.
    @discardableResult
    mutating func paste(_ text: String, at origin: CellAddress) -> [CellAddress] {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }

        var written: [CellAddress] = []
        for (rowOffset, line) in lines.enumerated() {
            for (columnOffset, field) in line.components(separatedBy: "\t").enumerated() {
                let address = CellAddress(column: origin.column + columnOffset, row: origin.row + rowOffset)
                guard contains(address) else { continue }
                let trimmed = field.trimmingCharacters(in: .whitespaces)
                inputs[address] = trimmed.isEmpty ? nil : trimmed
                written.append(address)
            }
        }
        recalculate()
        return written
    }

    /// Writes a block of inputs with `origin` as its top-left corner, the way
    /// a copied range is pasted with its formulas. Rows may be ragged; cells
    /// beyond the grid are dropped. Returns the cells written.
    @discardableResult
    mutating func setBlock(_ block: [[String]], at origin: CellAddress) -> [CellAddress] {
        var written: [CellAddress] = []
        for (rowOffset, row) in block.enumerated() {
            for (columnOffset, input) in row.enumerated() {
                let address = CellAddress(column: origin.column + columnOffset, row: origin.row + rowOffset)
                guard contains(address) else { continue }
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                inputs[address] = trimmed.isEmpty ? nil : trimmed
                written.append(address)
            }
        }
        recalculate()
        return written
    }

    // MARK: - Reading input

    static func isFormula(_ input: String) -> Bool {
        input.hasPrefix("=")
    }

    /// `input` as it should read after moving `columns` across and `rows`
    /// down, as when a copied formula is pasted elsewhere: `=A1+B2` copied one
    /// row down becomes `=A2+B3`. Every reference is relative. One pushed off
    /// the top or left edge becomes `#REF!`, as in a spreadsheet. Anything
    /// that isn't a formula comes back unchanged.
    static func shiftingReferences(in input: String, columns: Int, rows: Int) -> String {
        guard isFormula(input), columns != 0 || rows != 0 else { return input }
        let tokens = FormulaLexer.tokenize(input)
        let source = input as NSString
        var output = ""
        var position = 0
        for (index, token) in tokens.enumerated() {
            guard case .identifier(let name) = token.kind, let address = CellAddress(name) else { continue }
            // `LOG10(` is a function, not a cell.
            if index + 1 < tokens.count, case .leftParen = tokens[index + 1].kind { continue }
            output += source.substring(with: NSRange(location: position, length: token.range.lowerBound - position))
            let column = address.column + columns
            let row = address.row + rows
            output += column >= 0 && row >= 0 ? CellAddress(column: column, row: row).name : "#REF!"
            position = token.range.upperBound
        }
        output += source.substring(from: position)
        return output
    }

    /// What a cell that isn't a formula holds. Numbers may have thousands
    /// separators, a trailing `%`, or Khmer digits; anything else is text. A
    /// leading `'` keeps text that looks like a number or formula as text.
    static func literal(_ input: String) -> FormulaValue {
        if input.hasPrefix("'") { return .text(String(input.dropFirst())) }

        var text = String(input.unicodeScalars.map { scalar -> Character in
            if (0x80...0xFFFF).contains(scalar.value), let digit = FormulaLexer.digitValue(UInt16(scalar.value)) {
                return Character(String(digit))
            }
            return Character(scalar)
        })
        text.removeAll { $0 == "," || $0 == " " }
        let isPercent = text.hasSuffix("%")
        if isPercent { text.removeLast() }

        guard let first = text.first, "0123456789+-.".contains(first),
              let number = Double(text), number.isFinite else {
            return .text(input)
        }
        return isPercent ? .percent(number / 100) : .number(number)
    }

    // MARK: - Calculation

    private mutating func recalculate() {
        let pass = Recalculation(inputs: inputs, columns: columns, rows: rows, engine: engine)
        var results: [CellAddress: FormulaCalculation] = [:]
        for address in inputs.keys {
            results[address] = pass.result(at: address)
        }
        self.results = results
    }
}

/// One pass over the sheet. Each cell is worked out once, on first use, and
/// a cell that is reached again while it is still being worked out is part
/// of a cycle.
private final class Recalculation {
    private let inputs: [CellAddress: String]
    private let engine: FormulaEngine
    private var cells: FormulaCells!
    private var memo: [CellAddress: FormulaCalculation] = [:]
    private var inProgress: Set<CellAddress> = []

    init(inputs: [CellAddress: String], columns: Int, rows: Int, engine: FormulaEngine) {
        self.inputs = inputs
        self.engine = engine
        self.cells = FormulaCells(columns: columns, rows: rows) { [unowned self] address in
            try self.referencedValue(address)
        }
    }

    func result(at address: CellAddress) -> FormulaCalculation {
        if let known = memo[address] { return known }
        guard let input = inputs[address] else { return .empty }

        let result: FormulaCalculation
        if Spreadsheet.isFormula(input) {
            inProgress.insert(address)
            result = engine.calculate(input, cells: cells)
            inProgress.remove(address)
        } else {
            result = .value(Spreadsheet.literal(input), expression: input)
        }
        memo[address] = result
        return result
    }

    /// What a formula sees when it refers to `address`.
    private func referencedValue(_ address: CellAddress) throws -> FormulaValue? {
        if inProgress.contains(address) {
            throw FormulaError(.reference, "Circular reference: \(address.name) ends up depending on itself.")
        }
        switch result(at: address) {
        case .empty:
            return nil
        case .value(let value, _):
            return value
        case .failure(let error):
            // A cycle is reported as one everywhere along it; other errors
            // say where they came from.
            if error.kind == .reference, error.message.hasPrefix("Circular") { throw error }
            throw FormulaError(error.kind, "\(address.name) shows \(error.code), so this can't be worked out.")
        }
    }
}
