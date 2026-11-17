//
//  ExchangeRates.swift
//  Mini Khmer Dictionary
//
//  Foundation only; tested by Tools/test_formula_engine.sh.
//

import Foundation

/// A currency the converter knows.
struct Currency: Hashable, Identifiable, Sendable {
    let code: String
    let symbol: String
    let name: String
    let khmerName: String
    /// Digits after the point when shown: riel and dong have none.
    let fractionDigits: Int
    var region: Region = .asia
    /// `$12.50` rather than `12.50 $`.
    var symbolFirst = false
    
    enum Region: String, CaseIterable, Sendable {
        case asean = "Southeast Asia"
        case asia = "East & South Asia"
        case europe = "Europe"
        case americas = "Americas & Oceania"
        case middleEast = "Middle East & Africa"
    }
    
    var id: String { code }
    
    /// The image set in Assets.xcassets drawn as this currency's round flag:
    /// `flag-KHR`, `flag-USD`, … Any square image works; it is cropped to a
    /// circle. Without one, the symbol is shown in a coloured circle.
    var flagAssetName: String { "flag-\(code)" }
    
    static let all: [Currency] = [
        // Southeast Asia
        Currency(code: "KHR", symbol: "៛", name: "Cambodian riel", khmerName: "រៀល", fractionDigits: 0, region: .asean),
        Currency(code: "USD", symbol: "$", name: "US dollar", khmerName: "ដុល្លារ", fractionDigits: 2, region: .americas, symbolFirst: true),
        Currency(code: "THB", symbol: "฿", name: "Thai baht", khmerName: "បាត", fractionDigits: 2, region: .asean),
        Currency(code: "VND", symbol: "₫", name: "Vietnamese dong", khmerName: "ដុង", fractionDigits: 0, region: .asean),
        Currency(code: "LAK", symbol: "₭", name: "Lao kip", khmerName: "គីប", fractionDigits: 0, region: .asean),
        Currency(code: "MYR", symbol: "RM", name: "Malaysian ringgit", khmerName: "រីងហ្គីត", fractionDigits: 2, region: .asean),
        Currency(code: "SGD", symbol: "S$", name: "Singapore dollar", khmerName: "ដុល្លារសិង្ហបុរី", fractionDigits: 2, region: .asean, symbolFirst: true),
        Currency(code: "IDR", symbol: "Rp", name: "Indonesian rupiah", khmerName: "រូពីយ៉ាឥណ្ឌូណេស៊ី", fractionDigits: 0, region: .asean),
        Currency(code: "PHP", symbol: "₱", name: "Philippine peso", khmerName: "ប៉េសូហ្វីលីពីន", fractionDigits: 2, region: .asean),
        Currency(code: "MMK", symbol: "K", name: "Myanmar kyat", khmerName: "ចាតមីយ៉ាន់ម៉ា", fractionDigits: 0, region: .asean),
        Currency(code: "BND", symbol: "B$", name: "Brunei dollar", khmerName: "ដុល្លារព្រុយណេ", fractionDigits: 2, region: .asean, symbolFirst: true),
        // East and South Asia
        Currency(code: "CNY", symbol: "¥", name: "Chinese yuan", khmerName: "យាន់", fractionDigits: 2),
        Currency(code: "JPY", symbol: "¥", name: "Japanese yen", khmerName: "យ៉េន", fractionDigits: 0),
        Currency(code: "KRW", symbol: "₩", name: "South Korean won", khmerName: "វ៉ុន", fractionDigits: 0),
        Currency(code: "HKD", symbol: "HK$", name: "Hong Kong dollar", khmerName: "ដុល្លារហុងកុង", fractionDigits: 2, symbolFirst: true),
        Currency(code: "TWD", symbol: "NT$", name: "New Taiwan dollar", khmerName: "ដុល្លារតៃវ៉ាន់", fractionDigits: 0, symbolFirst: true),
        Currency(code: "INR", symbol: "₹", name: "Indian rupee", khmerName: "រូពីឥណ្ឌា", fractionDigits: 2, symbolFirst: true),
        // Europe
        Currency(code: "EUR", symbol: "€", name: "Euro", khmerName: "អឺរ៉ូ", fractionDigits: 2, region: .europe, symbolFirst: true),
        Currency(code: "GBP", symbol: "£", name: "British pound", khmerName: "ផោន", fractionDigits: 2, region: .europe, symbolFirst: true),
        Currency(code: "CHF", symbol: "CHF", name: "Swiss franc", khmerName: "ហ្វ្រង់ស្វីស", fractionDigits: 2, region: .europe),
        Currency(code: "SEK", symbol: "kr", name: "Swedish krona", khmerName: "ក្រូណាស៊ុយអែត", fractionDigits: 2, region: .europe),
        Currency(code: "NOK", symbol: "kr", name: "Norwegian krone", khmerName: "ក្រូណន័រវែស", fractionDigits: 2, region: .europe),
        Currency(code: "DKK", symbol: "kr", name: "Danish krone", khmerName: "ក្រូណដាណឺម៉ាក", fractionDigits: 2, region: .europe),
        Currency(code: "PLN", symbol: "zł", name: "Polish zloty", khmerName: "ស្ល៉ូទីប៉ូឡូញ", fractionDigits: 2, region: .europe),
        Currency(code: "RUB", symbol: "₽", name: "Russian ruble", khmerName: "រូប្លិ៍រុស្ស៊ី", fractionDigits: 2, region: .europe),
        Currency(code: "TRY", symbol: "₺", name: "Turkish lira", khmerName: "លីរ៉ាទួរគី", fractionDigits: 2, region: .europe),
        // Americas and Oceania
        Currency(code: "CAD", symbol: "C$", name: "Canadian dollar", khmerName: "ដុល្លារកាណាដា", fractionDigits: 2, region: .americas, symbolFirst: true),
        Currency(code: "MXN", symbol: "MX$", name: "Mexican peso", khmerName: "ប៉េសូម៉ិកស៊ិក", fractionDigits: 2, region: .americas, symbolFirst: true),
        Currency(code: "BRL", symbol: "R$", name: "Brazilian real", khmerName: "រៀលប្រេស៊ីល", fractionDigits: 2, region: .americas, symbolFirst: true),
        Currency(code: "AUD", symbol: "A$", name: "Australian dollar", khmerName: "ដុល្លារអូស្ត្រាលី", fractionDigits: 2, region: .americas, symbolFirst: true),
        Currency(code: "NZD", symbol: "NZ$", name: "New Zealand dollar", khmerName: "ដុល្លារនូវែលសេឡង់", fractionDigits: 2, region: .americas, symbolFirst: true),
        // Middle East and Africa
        Currency(code: "AED", symbol: "AED", name: "UAE dirham", khmerName: "ឌៀរហាមអេមីរ៉ាត", fractionDigits: 2, region: .middleEast),
        Currency(code: "SAR", symbol: "SAR", name: "Saudi riyal", khmerName: "រីយ៉ាល់អារ៉ាប៊ីសាអូឌីត", fractionDigits: 2, region: .middleEast),
        Currency(code: "QAR", symbol: "QAR", name: "Qatari riyal", khmerName: "រីយ៉ាល់កាតា", fractionDigits: 2, region: .middleEast),
        Currency(code: "KWD", symbol: "KD", name: "Kuwaiti dinar", khmerName: "ឌីណាគុយវ៉ែត", fractionDigits: 3, region: .middleEast),
        Currency(code: "ILS", symbol: "₪", name: "Israeli shekel", khmerName: "ស៊ិកែលអ៊ីស្រាអែល", fractionDigits: 2, region: .middleEast, symbolFirst: true),
        Currency(code: "EGP", symbol: "E£", name: "Egyptian pound", khmerName: "ផោនអេហ្ស៊ីប", fractionDigits: 2, region: .middleEast),
        Currency(code: "ZAR", symbol: "R", name: "South African rand", khmerName: "រ៉ង់អាហ្វ្រិកខាងត្បូង", fractionDigits: 2, region: .middleEast),
    ]
    
    static func named(_ code: String) -> Currency? {
        all.first { $0.code == code.uppercased() }
    }
    
    /// `12,500 ៛`, `$12.50`, `1,200 ฿`.
    func format(_ amount: Double, grouping: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let number = formatter.string(from: NSNumber(value: abs(amount))) ?? String(abs(amount))
        let sign = amount < 0 && number.contains(where: { $0 != "0" && $0 != "." && $0 != "," }) ? "-" : ""
        return symbolFirst ? sign + symbol + number : sign + number + " " + symbol
    }
}

/// How many of each currency one US dollar buys, kept in user defaults and
/// editable, with an optional online update.
///
/// Thread-safe: formulas read it through `FX(…)` while the Tools panel edits
/// it.
final class ExchangeRates: @unchecked Sendable {
    static let shared = ExchangeRates()
    
    /// Starting points only, shown as "set by hand" until updated: rates move
    /// daily, and the riel in particular should be checked against the
    /// National Bank of Cambodia's rate.
    static let defaults: [String: Double] = [
        "USD": 1, "KHR": 4_100, "THB": 33, "VND": 26_000, "LAK": 21_500, "MYR": 4.2, "SGD": 1.3,
        "IDR": 16_000, "PHP": 57, "MMK": 2_100, "BND": 1.3,
        "CNY": 7.1, "JPY": 150, "KRW": 1_400, "HKD": 7.8, "TWD": 32, "INR": 85,
        "EUR": 0.86, "GBP": 0.76, "CHF": 0.88, "SEK": 10.5, "NOK": 10.8, "DKK": 6.4, "PLN": 3.9,
        "RUB": 90, "TRY": 34, "CAD": 1.38, "MXN": 18, "BRL": 5.5, "AUD": 1.53, "NZD": 1.7,
        "AED": 3.6725, "SAR": 3.75, "QAR": 3.64, "KWD": 0.307, "ILS": 3.7, "EGP": 49, "ZAR": 18,
    ]
    
    private let lock = NSLock()
    private var rates: [String: Double]
    private var updated: Date?
    private var source: String?
    private let defaults: UserDefaults
    
    private static let ratesKey = "exchangeRates"
    private static let updatedKey = "exchangeRatesUpdated"
    private static let sourceKey = "exchangeRatesSource"
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var stored = Self.defaults
        if let saved = defaults.dictionary(forKey: Self.ratesKey) as? [String: Double] {
            stored.merge(saved.filter { $0.value > 0 && $0.value.isFinite }) { $1 }
        }
        rates = stored
        updated = defaults.object(forKey: Self.updatedKey) as? Date
        source = defaults.string(forKey: Self.sourceKey)
    }
    
    /// Units of `code` per US dollar.
    func rate(_ code: String) -> Double? {
        lock.withLock { rates[code.uppercased()] }
    }
    
    var snapshot: (rates: [String: Double], updated: Date?, source: String?) {
        lock.withLock { (rates, updated, source) }
    }
    
    /// `amount` of `from` in `to`, or `nil` for a currency without a rate.
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let fromRate = rate(from), let toRate = rate(to), fromRate > 0 else { return nil }
        return amount / fromRate * toRate
    }
    
    /// Sets one rate by hand.
    func setRate(_ value: Double, for code: String) {
        guard value > 0, value.isFinite, code.uppercased() != "USD" else { return }
        lock.withLock {
            rates[code.uppercased()] = value
            source = "Set by hand"
        }
        save()
    }
    
    func resetToDefaults() {
        lock.withLock {
            rates = Self.defaults
            updated = nil
            source = nil
        }
        save()
    }
    
    /// Replaces every known rate at once, e.g. from `fetchLatest()`.
    func apply(_ fetched: [String: Double], updated date: Date, source name: String) {
        lock.withLock {
            for currency in Currency.all {
                if let value = fetched[currency.code], value > 0, value.isFinite { rates[currency.code] = value }
            }
            rates["USD"] = 1
            updated = date
            source = name
        }
        save()
    }
    
    private func save() {
        let (rates, updated, source) = snapshot
        defaults.set(rates, forKey: Self.ratesKey)
        defaults.set(updated, forKey: Self.updatedKey)
        defaults.set(source, forKey: Self.sourceKey)
    }
    
    // MARK: - Online
    
    enum FetchError: LocalizedError {
        case badResponse
        var errorDescription: String? { "The exchange-rate service didn't answer as expected. Your current rates are unchanged." }
    }
    
    /// Today's market rates per US dollar from a free public service (no
    /// account or key). Nothing about the user is sent.
    static func fetchLatest() async throws -> (rates: [String: Double], updated: Date) {
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FetchError.badResponse }
        return try parse(data)
    }
    
    static func parse(_ data: Data) throws -> (rates: [String: Double], updated: Date) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["result"] as? String == "success",
              let rates = json["rates"] as? [String: Any] else { throw FetchError.badResponse }
        let numbers = rates.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        let stamp = (json["time_last_update_unix"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
        return (numbers, stamp)
    }
    
    // MARK: - Mixed amounts
    
    /// Compiled patterns, kept: the Money tab reads its amount on every
    /// redraw, and compiling some eighty patterns each time made typing lag.
    private static let patternCache = PatternCache()
    
    private final class PatternCache: @unchecked Sendable {
        let lock = NSLock()
        var patterns: [String: NSRegularExpression] = [:]
    }
    
    private static func compiled(_ pattern: String) -> NSRegularExpression {
        patternCache.lock.withLock {
            if let known = patternCache.patterns[pattern] { return known }
            let made = try! NSRegularExpression(pattern: pattern)
            patternCache.patterns[pattern] = made
            return made
        }
    }
    
    /// Reads amounts written with currency signs or codes — `$12 + 5000៛`,
    /// `12 usd - 3,000 riel`, `100฿ * 2` — as one calculation in US dollars,
    /// for the formula engine to work out. Numbers without a currency stay
    /// plain numbers, so `* 2` still doubles. Returns `nil` when the text
    /// names no currency at all.
    func dollarExpression(from text: String) -> String? {
        let known: [(pattern: String, code: String)] = [
            ("riels?|រៀល|khr|៛", "KHR"), ("dollars?|ដុល្លារ|usd|\\$", "USD"), ("baht|បាត|thb|฿", "THB"),
            ("dong|ដុង|vnd|₫", "VND"), ("euros?|eur|€", "EUR"), ("yuan|cny|rmb", "CNY"), ("yen|jpy", "JPY"),
            ("won|krw|₩", "KRW"), ("pounds?|gbp|£", "GBP"), ("sgd", "SGD"), ("myr|rm", "MYR"), ("kip|lak|₭", "LAK"), ("aud", "AUD"),
            ("rupees?|inr|₹", "INR"), ("pesos?|php|₱", "PHP"), ("rupiah|idr", "IDR"), ("rubles?|rub|₽", "RUB"),
            ("lira|try|₺", "TRY"), ("shekels?|ils|₪", "ILS"),
        ]
        // Every other currency by its code: 20 hkd, cad 15.
        let named = Set(known.map(\.code))
        let names = known + Currency.all.filter { !named.contains($0.code) }.map { ($0.code.lowercased(), $0.code) }
        let number = "([0-9][0-9,]*(?:\\.[0-9]+)?)"
        var output = KhmerNumbers.westernDigits(text)
        var found = false
        for (pattern, code) in names {
            guard let rate = rate(code) else { continue }
            for regex in [
                "(?i)(?<![a-z])(?:\(pattern))\\s*" + number,     // $12, usd 12
                "(?i)" + number + "\\s*(?:\(pattern))(?![a-z])",  // 12$, 5000 riel
            ] {
                let expression = Self.compiled(regex)
                let source = output as NSString
                var rebuilt = ""
                var cursor = 0
                for match in expression.matches(in: output, range: NSRange(location: 0, length: source.length)) {
                    let amount = source.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                    rebuilt += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                    rebuilt += "(\(amount)/\(FormulaFormatter.plain(rate)))"
                    cursor = NSMaxRange(match.range)
                    found = true
                }
                rebuilt += source.substring(from: cursor)
                output = rebuilt
            }
        }
        return found ? output : nil
    }
}
