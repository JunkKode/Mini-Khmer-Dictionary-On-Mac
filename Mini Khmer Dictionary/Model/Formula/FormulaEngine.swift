//
//  FormulaEngine.swift
//  Mini Khmer Dictionary
//

import Foundation

/// The outcome of calculating one piece of input.
enum FormulaCalculation: Equatable {
    case empty
    /// `expression` is the input as the engine understood it, e.g.
    /// `SUM(100, 200, 300)` for `=sum(100,200,300)`.
    case value(FormulaValue, expression: String)
    case failure(FormulaError)

    var value: FormulaValue? {
        if case .value(let value, _) = self { return value }
        return nil
    }

    var error: FormulaError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

/// Parses and evaluates formulas against a function registry. Pure: no UI, no
/// state, safe to call on every keystroke.
struct FormulaEngine {
    var functions: FormulaFunctionRegistry = .standard

    /// `cells` lets the formula use references such as `A1` and `SUM(A1:A5)`.
    func calculate(_ source: String, cells: FormulaCells? = nil) -> FormulaCalculation {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        do {
            let expression = try FormulaParser.parse(source)
            let value = try FormulaEvaluator(functions: functions, cells: cells).evaluate(expression)
            return .value(value, expression: expression.canonicalText)
        } catch let error as FormulaError {
            return .failure(error)
        } catch {
            return .failure(FormulaError(.syntax, error.localizedDescription))
        }
    }

    /// Convenience for tests and callers that want `throws`.
    func evaluate(_ source: String) throws -> FormulaValue {
        switch calculate(source) {
        case .empty: throw FormulaError(.incomplete, "Nothing to calculate.")
        case .value(let value, _): return value
        case .failure(let error): throw error
        }
    }
}

// MARK: - Formatting

/// Turns values into text. Numbers always use "." for decimals and "," for
/// thousands, matching what the formula language accepts.
enum FormulaFormatter {
    /// At most this many decimal places are shown; beyond it binary floating
    /// point noise (0.1 + 0.2) shows through.
    static let maximumFractionDigits = 10

    /// For reading: `1,234.5`.
    static func display(_ value: Double) -> String {
        format(value, grouping: true)
    }

    /// For copying and re-entering: `1234.5`.
    static func plain(_ value: Double) -> String {
        format(value, grouping: false)
    }

    static func display(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// `fractionDigits` caps the decimals, e.g. for narrow Grid cells.
    static func display(_ value: FormulaValue, fractionDigits: Int = maximumFractionDigits) -> String {
        switch value {
        case .number(let number): format(number, grouping: true, fractionDigits: fractionDigits)
        case .percent(let fraction): format(fraction * 100, grouping: true, fractionDigits: fractionDigits) + "%"
        case .text(let text): text
        case .boolean(let flag): flag ? "TRUE" : "FALSE"
        case .date(let date): display(date)
        }
    }

    static func plain(_ value: FormulaValue) -> String {
        switch value {
        case .number(let number): plain(number)
        case .percent(let fraction): plain(fraction * 100) + "%"
        default: display(value)
        }
    }

    private static func format(_ value: Double, grouping: Bool, fractionDigits: Int = maximumFractionDigits) -> String {
        guard value.isFinite else { return value.isNaN ? "NaN" : (value < 0 ? "-∞" : "∞") }
        if value == 0 { return "0" }

        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-9 {
            return scientific(value)
        }

        // 15 significant digits is all a double reliably holds; cap decimals
        // after that so 0.1 + 0.2 reads 0.3.
        let significant = String(format: "%.15g", value)
        guard var decimal = Decimal(string: significant, locale: posix) else { return significant }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, min(fractionDigits, maximumFractionDigits), .plain)
        return (grouping ? groupedFormatter : plainFormatter).string(from: rounded as NSDecimalNumber) ?? significant
    }

    private static func scientific(_ value: Double) -> String {
        // 1.23456789E+20, with trailing zeros of the mantissa dropped.
        let raw = String(format: "%.10E", value)
        guard let marker = raw.firstIndex(of: "E") else { return raw }
        var mantissa = String(raw[..<marker])
        if mantissa.contains(".") {
            while mantissa.hasSuffix("0") { mantissa.removeLast() }
            if mantissa.hasSuffix(".") { mantissa.removeLast() }
        }
        var exponent = String(raw[raw.index(after: marker)...])
        // E+05 → E+5
        let sign = exponent.first.map(String.init) ?? "+"
        exponent = String(exponent.dropFirst().drop { $0 == "0" })
        return "\(mantissa)E\(sign)\(exponent.isEmpty ? "0" : exponent)"
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private static let groupedFormatter = makeFormatter(grouping: true)
    private static let plainFormatter = makeFormatter(grouping: false)

    private static func makeFormatter(grouping: Bool) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = posix
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minusSign = "-"
        return formatter
    }
}
