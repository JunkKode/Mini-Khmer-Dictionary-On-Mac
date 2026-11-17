//
//  CalculatorTools.swift
//  Mini Khmer Dictionary
//
//  Unit conversion, loans and date arithmetic behind the Calculator's Tools
//  panels. Foundation only; tested by Tools/test_formula_engine.sh.
//

import Foundation

// MARK: - Units

/// A unit, as a multiple of its category's base unit.
struct MeasureUnit: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let khmerName: String
    /// How many base units one of this is: grams, metres, square metres or
    /// litres.
    let factor: Double
    /// A Cambodian unit whose exact size varies by place and trade.
    var isTraditional = false
}

enum MeasureCategory: String, CaseIterable, Identifiable, Sendable {
    case weight, length, area, volume, temperature
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
            case .weight: "Weight & gold"
            case .length: "Length"
            case .area: "Area & land"
            case .volume: "Volume"
            case .temperature: "Temperature"
        }
    }
    
    var units: [MeasureUnit] {
        switch self {
            case .weight: [
                MeasureUnit(id: "g", name: "Gram", khmerName: "ក្រាម", factor: 1),
                MeasureUnit(id: "kg", name: "Kilogram", khmerName: "គីឡូក្រាម", factor: 1_000),
                MeasureUnit(id: "t", name: "Tonne", khmerName: "តោន", factor: 1_000_000),
                MeasureUnit(id: "damlung", name: "Damlung (tael)", khmerName: "ដំឡឹង", factor: GoldWeight.gramsPerDamlung, isTraditional: true),
                MeasureUnit(id: "chi", name: "Chi", khmerName: "ជី", factor: GoldWeight.gramsPerDamlung / 10, isTraditional: true),
                MeasureUnit(id: "hun", name: "Hun", khmerName: "ហ៊ុន", factor: GoldWeight.gramsPerDamlung / 100, isTraditional: true),
                MeasureUnit(id: "li", name: "Li", khmerName: "លី", factor: GoldWeight.gramsPerDamlung / 1_000, isTraditional: true),
                MeasureUnit(id: "ozt", name: "Troy ounce", khmerName: "អោនមាស", factor: 31.1034768),
                MeasureUnit(id: "oz", name: "Ounce", khmerName: "អោន", factor: 28.349523125),
                MeasureUnit(id: "lb", name: "Pound", khmerName: "ផោន", factor: 453.59237),
            ]
            case .length: [
                MeasureUnit(id: "m", name: "Metre", khmerName: "ម៉ែត្រ", factor: 1),
                MeasureUnit(id: "cm", name: "Centimetre", khmerName: "សង់ទីម៉ែត្រ", factor: 0.01),
                MeasureUnit(id: "mm", name: "Millimetre", khmerName: "មីលីម៉ែត្រ", factor: 0.001),
                MeasureUnit(id: "km", name: "Kilometre", khmerName: "គីឡូម៉ែត្រ", factor: 1_000),
                MeasureUnit(id: "in", name: "Inch", khmerName: "អ៊ីញ", factor: 0.0254),
                MeasureUnit(id: "ft", name: "Foot", khmerName: "ហ្វីត", factor: 0.3048),
                MeasureUnit(id: "yd", name: "Yard", khmerName: "យ៉ាត", factor: 0.9144),
                MeasureUnit(id: "mi", name: "Mile", khmerName: "ម៉ាយ", factor: 1_609.344),
                MeasureUnit(id: "hat", name: "Hat (cubit)", khmerName: "ហត្ថ", factor: 0.5, isTraditional: true),
                MeasureUnit(id: "pyeam", name: "Pyeam (fathom)", khmerName: "ព្យាម", factor: 2, isTraditional: true),
                MeasureUnit(id: "sen", name: "Sen", khmerName: "សិន", factor: 40, isTraditional: true),
            ]
            case .area: [
                MeasureUnit(id: "m2", name: "Square metre", khmerName: "ម៉ែត្រការ៉េ", factor: 1),
                MeasureUnit(id: "are", name: "Are", khmerName: "អា", factor: 100),
                MeasureUnit(id: "ha", name: "Hectare", khmerName: "ហិកតា", factor: 10_000),
                MeasureUnit(id: "km2", name: "Square kilometre", khmerName: "គីឡូម៉ែត្រការ៉េ", factor: 1_000_000),
                MeasureUnit(id: "ft2", name: "Square foot", khmerName: "ហ្វីតការ៉េ", factor: 0.09290304),
                MeasureUnit(id: "acre", name: "Acre", khmerName: "អាគ្រ", factor: 4_046.8564224),
            ]
            case .volume: [
                MeasureUnit(id: "l", name: "Litre", khmerName: "លីត្រ", factor: 1),
                MeasureUnit(id: "ml", name: "Millilitre", khmerName: "មីលីលីត្រ", factor: 0.001),
                MeasureUnit(id: "m3", name: "Cubic metre", khmerName: "ម៉ែត្រគូប", factor: 1_000),
                MeasureUnit(id: "gal", name: "US gallon", khmerName: "ហ្គាឡុង", factor: 3.785411784),
            ]
            case .temperature: [
                MeasureUnit(id: "c", name: "Celsius", khmerName: "អង្សាសេ", factor: 1),
                MeasureUnit(id: "f", name: "Fahrenheit", khmerName: "ហ្វារិនហៃ", factor: 1),
                MeasureUnit(id: "k", name: "Kelvin", khmerName: "កែលវិន", factor: 1),
            ]
        }
    }
    
    /// `value` in `from`, expressed in `to`.
    func convert(_ value: Double, from: MeasureUnit, to: MeasureUnit) -> Double {
        guard self == .temperature else { return value * from.factor / to.factor }
        let celsius: Double = switch from.id {
            case "f": (value - 32) * 5 / 9
            case "k": value - 273.15
            default: value
        }
        return switch to.id {
            case "f": celsius * 9 / 5 + 32
            case "k": celsius + 273.15
            default: celsius
        }
    }
}

/// Gold as it is weighed and priced in Cambodia: by the ដំឡឹង (damlung, a
/// tael of 37.5 g) and its tenths — ជី, ហ៊ុន, លី.
enum GoldWeight {
    static let gramsPerDamlung = 37.5
    static let gramsPerTroyOunce = 31.1034768
    
    /// The price of `grams` of gold when one ដំឡឹង costs `pricePerDamlung`.
    static func value(grams: Double, pricePerDamlung: Double) -> Double {
        grams / gramsPerDamlung * pricePerDamlung
    }
    
    /// A world price per troy ounce turned into a price per ដំឡឹង.
    static func damlungPrice(fromOuncePrice price: Double) -> Double {
        price / gramsPerTroyOunce * gramsPerDamlung
    }
    
    /// `12.5 g` as ដំឡឹង, ជី, ហ៊ុន and លី: 3 ជី 3 ហ៊ុន 3 លី.
    static func breakdown(grams: Double) -> [(unit: String, count: Int)] {
        var li = Int((grams / (gramsPerDamlung / 1_000)).rounded())
        var parts: [(String, Int)] = []
        for (name, size) in [("ដំឡឹង", 1_000), ("ជី", 100), ("ហ៊ុន", 10), ("លី", 1)] where li >= size {
            parts.append((name, li / size))
            li %= size
        }
        return parts
    }
}

// MARK: - Loans

enum LoanMethod: String, CaseIterable, Identifiable, Sendable {
    /// The same payment every month (annuity) — most bank loans.
    case equalPayments
    /// The same principal every month, interest on what is still owed, so
    /// payments shrink — common with microfinance.
    case equalPrincipal
    /// Interest on the full amount every month, however much is repaid.
    case flat
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
            case .equalPayments: "Equal payments"
            case .equalPrincipal: "Declining payments"
            case .flat: "Flat rate"
        }
    }
}

struct LoanSchedule: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        let month: Int
        let payment: Double
        let principal: Double
        let interest: Double
        let balance: Double
        var id: Int { month }
    }
    
    let rows: [Row]
    
    var firstPayment: Double { rows.first?.payment ?? 0 }
    var lastPayment: Double { rows.last?.payment ?? 0 }
    var totalInterest: Double { rows.reduce(0) { $0 + $1.interest } }
    var totalPaid: Double { rows.reduce(0) { $0 + $1.payment } }
    
    /// `monthlyRate` is a fraction per month (1.5% a month is 0.015).
    init(principal: Double, monthlyRate: Double, months: Int, method: LoanMethod) {
        guard principal > 0, months > 0, months <= 1_200, monthlyRate >= 0, monthlyRate.isFinite else {
            rows = []
            return
        }
        var rows: [Row] = []
        var balance = principal
        let share = principal / Double(months)
        let annuity = monthlyRate == 0
        ? share
        : principal * monthlyRate / (1 - pow(1 + monthlyRate, -Double(months)))
        
        for month in 1...months {
            let interest: Double
            let repaid: Double
            switch method {
                case .equalPayments:
                    interest = balance * monthlyRate
                    repaid = month == months ? balance : annuity - interest
                case .equalPrincipal:
                    interest = balance * monthlyRate
                    repaid = month == months ? balance : share
                case .flat:
                    interest = principal * monthlyRate
                    repaid = month == months ? balance : share
            }
            balance = max(0, balance - repaid)
            rows.append(Row(month: month, payment: repaid + interest, principal: repaid, interest: interest, balance: balance))
        }
        self.rows = rows
    }
}

// MARK: - Dates

enum DateMath {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
    
    /// Whole days from `start` to `end`, negative when `end` comes first.
    static func days(from start: Date, to end: Date) -> Int {
        let calendar = calendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
    
    /// The gap as years, months and days, the way an age is said.
    static func span(from start: Date, to end: Date) -> (years: Int, months: Int, days: Int) {
        let calendar = calendar
        let (from, to) = start <= end ? (start, end) : (end, start)
        let parts = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to))
        return (parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    
    static func adding(days: Int = 0, months: Int = 0, years: Int = 0, to date: Date) -> Date {
        var components = DateComponents()
        components.day = days
        components.month = months
        components.year = years
        return calendar.date(byAdding: components, to: calendar.startOfDay(for: date)) ?? date
    }
    
    /// Monday-to-Friday days from `start` up to and including `end`.
    static func workingDays(from start: Date, to end: Date) -> Int {
        let calendar = calendar
        let (from, to) = start <= end ? (start, end) : (end, start)
        var day = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: to)
        var count = 0
        while day <= last, count < 100_000 {
            let weekday = calendar.component(.weekday, from: day)
            if weekday != 1 && weekday != 7 { count += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }
    
    /// ថ្ងៃច័ន្ទ ទី១៧ ខែវិច្ឆិកា ឆ្នាំ២០២៦ — the solar date in Khmer.
    static func khmerSolarDate(_ date: Date) -> String {
        KhmerDateText.solar(date)
    }
}
