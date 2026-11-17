//
//  FormulaKhmerFunctions.swift
//  Mini Khmer Dictionary
//
//  Khmer numbers, money, exchange rates, loans and dates as formula
//  functions, so Smart and Grid can use what the Tools panels do. Depends on
//  Model/Calculator (Foundation only); tested by Tools/test_formula_engine.sh.
//

import Foundation

extension FormulaFunctionRegistry {
    static let khmerFunctions: [FormulaFunction] = [
        FormulaFunction(
            "KHMERWORDS", category: .khmer, parameters: ["number"],
            summary: "The number in Khmer words.", example: "KHMERWORDS(1250000)"
        ) { args in
            guard let words = KhmerNumbers.words(for: try args.number(0)) else {
                throw FormulaError(.number, "KHMERWORDS can't say a number that large.")
            }
            return .text(words)
        },
        FormulaFunction(
            "KHMERMONEY", category: .khmer, parameters: ["amount", "[currency]"],
            summary: "An amount of money in Khmer words: riel by default, or \"USD\".", example: "KHMERMONEY(25000)"
        ) { args in
            let code = args.count > 1 ? try args.text(1) : "KHR"
            guard let currency = Currency.named(code) else {
                throw FormulaError(.value, "KHMERMONEY doesn't know the currency “\(code)”.")
            }
            guard let words = KhmerNumbers.moneyWords(for: try args.number(0), currency: currency) else {
                throw FormulaError(.number, "KHMERMONEY can't say an amount that large.")
            }
            return .text(words)
        },
        FormulaFunction(
            "KHMERDIGITS", category: .khmer, parameters: ["value"],
            summary: "The value written with Khmer digits.", example: "KHMERDIGITS(2026)"
        ) { args in
            let value = try args.value(0)
            if case .text(let text) = value { return .text(KhmerNumbers.digits(text)) }
            return .text(KhmerNumbers.digits(FormulaFormatter.display(value)))
        },
        FormulaFunction(
            "FX", category: .finance, parameters: ["amount", "from", "to"],
            summary: "Converts money between currencies at the rates set in Tools › Currency.", example: "FX(100, \"USD\", \"KHR\")"
        ) { args in
            let amount = try args.number(0)
            let from = try args.text(1), to = try args.text(2)
            guard let value = ExchangeRates.shared.convert(amount, from: from, to: to) else {
                throw FormulaError(.value, "FX has no rate for “\(Currency.named(from) == nil ? from : to)”.")
            }
            return .number(value)
        },
        FormulaFunction(
            "PMT", category: .finance, parameters: ["rate", "periods", "principal"],
            summary: "The payment per period on a loan, negative as in a spreadsheet. Rate is per period: 12%/12.",
            example: "PMT(12%/12, 24, 5000)"
        ) { args in
            let rate = try args.number(0)
            let periods = try args.number(1)
            let principal = try args.number(2)
            guard periods >= 1 else { throw FormulaError(.number, "PMT needs at least one period.") }
            let payment = rate == 0 ? principal / periods : principal * rate / (1 - pow(1 + rate, -periods))
            guard payment.isFinite else { throw FormulaError(.number, "PMT's result is out of range.") }
            return .number(-payment)
        },
        FormulaFunction(
            "DATE", category: .date, parameters: ["year", "month", "day"],
            summary: "The date with the given year, month and day.", example: "DATE(2026, 4, 14)"
        ) { args in
            let year = try args.number(0)
            guard (1...9999).contains(year) else { throw FormulaError(.number, "DATE's year must be from 1 to 9999.") }
            var parts = DateComponents()
            parts.year = Int(year)
            parts.month = try args.integer(1, name: "month")
            parts.day = try args.integer(2, name: "day")
            // Out-of-range months and days roll over, as in a spreadsheet.
            guard let date = DateMath.calendar.date(from: parts) else {
                throw FormulaError(.number, "DATE can't make that date.")
            }
            return .date(date)
        },
        FormulaFunction(
            "DAYS", category: .date, parameters: ["end", "start"],
            summary: "Days from start to end.", example: "DAYS(DATE(2026, 12, 31), TODAY())"
        ) { args in
            .number(Double(DateMath.days(from: try formulaDate(args, 1), to: try formulaDate(args, 0))))
        },
        FormulaFunction(
            "EDATE", category: .date, parameters: ["start", "months"],
            summary: "The date some months before or after start.", example: "EDATE(TODAY(), 6)"
        ) { args in
            .date(DateMath.adding(months: try args.integer(1, name: "months"), to: try formulaDate(args, 0)))
        },
        FormulaFunction(
            "LUNAR", category: .khmer, parameters: ["[date]"],
            summary: "The date in the Khmer lunar calendar.", example: "LUNAR(TODAY())"
        ) { args in
            let date = args.count > 0 ? try formulaDate(args, 0) : FormulaDate.today()
            guard let lunar = KhmerLunarCalendar.date(for: date) else {
                throw FormulaError(.number, "LUNAR works for years \(KhmerLunarCalendar.supportedYears.lowerBound)–\(KhmerLunarCalendar.supportedYears.upperBound).")
            }
            return .text(lunar.fullText)
        },
    ]

    /// A date argument: a date, or a spreadsheet serial number.
    private static func formulaDate(_ args: FormulaArguments, _ index: Int) throws -> Date {
        let value = try args.value(index)
        if case .date(let date) = value { return date }
        return try FormulaDate.date(fromSerial: value.asNumber(context: args.functionName))
    }
}
