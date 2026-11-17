//
//  FormulaValue.swift
//  Mini Khmer Dictionary
//
//  The formula engine (everything in Model/Formula) depends on Foundation only,
//  so it can be compiled and tested on its own — see Tools/test_formula_engine.sh.
//

import Foundation

/// A value produced while evaluating a formula.
enum FormulaValue: Equatable {
    case number(Double)
    case text(String)
    case boolean(Bool)
    /// A calendar day, as produced by `TODAY()`. Arithmetic treats it as a
    /// spreadsheet serial number (days since 1899-12-30).
    case date(Date)
    /// A percentage, stored as a fraction: `15%` is `.percent(0.15)`. It
    /// calculates like the plain number but shows as `15%`, and percentage
    /// functions know it is already a rate.
    case percent(Double)

    var typeName: String {
        switch self {
        case .number: "number"
        case .percent: "percentage"
        case .text: "text"
        case .boolean: "logical value"
        case .date: "date"
        }
    }
}

/// Why a formula could not be evaluated. Always reported, never thrown past the
/// engine as anything else.
struct FormulaError: Error, Equatable {
    enum Kind: Equatable {
        /// Malformed input, e.g. `2 + * 3`.
        case syntax
        /// Input that is fine so far but stops early, e.g. `SUM(1, 2`.
        /// The editor treats this gently while the user is still typing.
        case incomplete
        /// A function or name the registry doesn't know.
        case unknownName
        /// Too few or too many arguments.
        case argumentCount
        /// A value of the wrong type, e.g. `"abc" * 2`.
        case value
        case divisionByZero
        /// A numeric result that doesn't exist or overflows, e.g. `SQRT(-1)`.
        case number
        /// A cell that doesn't exist, or cells that depend on each other.
        case reference
    }

    let kind: Kind
    let message: String
    /// UTF-16 offsets into the source of the part at fault, when known.
    var range: Range<Int>?

    init(_ kind: Kind, _ message: String, range: Range<Int>? = nil) {
        self.kind = kind
        self.message = message
        self.range = range
    }

    /// Spreadsheet-style short code shown next to the message.
    var code: String {
        switch kind {
        case .syntax, .incomplete: "#ERROR!"
        case .unknownName: "#NAME?"
        case .argumentCount, .value: "#VALUE!"
        case .divisionByZero: "#DIV/0!"
        case .number: "#NUM!"
        case .reference: "#REF!"
        }
    }
}

// MARK: - Coercion

extension FormulaValue {
    /// The value as a number, following spreadsheet rules: `TRUE` is 1, text is
    /// accepted only when it reads as a number.
    func asNumber(context: String? = nil) throws -> Double {
        switch self {
        case .number(let value), .percent(let value):
            return value
        case .boolean(let flag):
            return flag ? 1 : 0
        case .date(let date):
            return Double(FormulaDate.serial(of: date))
        case .text(let text):
            if let value = Double(text.trimmingCharacters(in: .whitespaces)) {
                return value
            }
            let prefix = context.map { "\($0) expects a number" } ?? "Expected a number"
            throw FormulaError(.value, "\(prefix), but got the text “\(text)”.")
        }
    }

    /// The value as true/false: numbers are true when non-zero.
    func asBoolean(context: String? = nil) throws -> Bool {
        switch self {
        case .boolean(let flag):
            return flag
        case .number(let value), .percent(let value):
            return value != 0
        case .date:
            return true
        case .text(let text):
            switch text.uppercased() {
            case "TRUE": return true
            case "FALSE": return false
            default:
                let prefix = context.map { "\($0) expects TRUE or FALSE" } ?? "Expected TRUE or FALSE"
                throw FormulaError(.value, "\(prefix), but got the text “\(text)”.")
            }
        }
    }

    /// The value as text, the way `CONCAT` and `&` see it.
    var asText: String {
        switch self {
        case .text(let text): text
        case .number(let value): FormulaFormatter.plain(value)
        case .percent: FormulaFormatter.plain(self)
        case .boolean(let flag): flag ? "TRUE" : "FALSE"
        case .date(let date): FormulaFormatter.display(date)
        }
    }
}

// MARK: - Dates

enum FormulaDate {
    private static var calendar: Calendar { Calendar.current }

    /// 1899-12-30, the day before spreadsheet serial number 1 (with the usual
    /// Lotus leap-year quirk folded in, so modern dates match Excel).
    private static var epoch: Date {
        calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))!
    }

    static func today() -> Date {
        calendar.startOfDay(for: Date())
    }

    static func serial(of date: Date) -> Int {
        calendar.dateComponents([.day], from: epoch, to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func date(fromSerial serial: Double) throws -> Date {
        guard serial.isFinite, abs(serial) < 3_000_000,
              let date = calendar.date(byAdding: .day, value: Int(serial.rounded(.down)), to: epoch) else {
            throw FormulaError(.number, "That date is out of range.")
        }
        return date
    }
}
