//
//  KhmerNumbers.swift
//  Mini Khmer Dictionary
//
//  Foundation only; tested by Tools/test_formula_engine.sh.
//

import Foundation

/// Numbers written the Khmer way: in words, for receipts and cheques, and in
/// Khmer digits.
enum KhmerNumbers {
    private static let units = ["សូន្យ", "មួយ", "ពីរ", "បី", "បួន", "ប្រាំ", "ប្រាំមួយ", "ប្រាំពីរ", "ប្រាំបី", "ប្រាំបួន"]
    private static let tens = ["", "ដប់", "ម្ភៃ", "សាមសិប", "សែសិប", "ហាសិប", "ហុកសិប", "ចិតសិប", "ប៉ែតសិប", "កៅសិប"]
    
    /// ១២៣៤ for 1234: Western digits swapped for Khmer ones, everything else
    /// kept.
    static func digits(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            ("0"..."9").contains(scalar) ? Unicode.Scalar(scalar.value - 0x30 + 0x17E0)! : scalar
        }))
    }
    
    /// 1234 for ១២៣៤.
    static func westernDigits(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x17E0...0x17E9).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0x17E0 + 0x30)! : scalar
        }))
    }
    
    /// The number in Khmer words: 1,250,000 is មួយលានពីរសែនប្រាំម៉ឺន, 12.05 is
    /// ដប់ពីរចុចសូន្យប្រាំ. Below a million it counts in សែន (100,000) and
    /// ម៉ឺន (10,000), as people say amounts; above, in លាន and ពាន់លាន.
    /// `nil` when the number is too large or not finite to say sensibly.
    static func words(for value: Double, fractionDigits: Int = 6) -> String? {
        guard value.isFinite, abs(value) < 1e15 else { return nil }
        let rounded = (abs(value) * pow(10, Double(fractionDigits))).rounded() / pow(10, Double(fractionDigits))
        let whole = UInt64(rounded.rounded(.down))
        var text = words(forWhole: whole)
        
        // The fraction is read digit by digit after ចុច ("point").
        let fraction = String(format: "%.\(fractionDigits)f", rounded - Double(whole))
            .split(separator: ".").dropFirst().first.map(String.init) ?? ""
        let trimmed = fraction.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        if !trimmed.isEmpty {
            text += "ចុច" + trimmed.map { units[Int(String($0))!] }.joined()
        }
        return value < 0 && rounded != 0 ? "ដក" + text : text
    }
    
    static func words(forWhole value: UInt64) -> String {
        if value == 0 { return units[0] }
        var parts: [String] = []
        var remainder = value
        if remainder >= 1_000_000 {
            parts.append(words(forWhole: remainder / 1_000_000) + "លាន")
            remainder %= 1_000_000
        }
        let places: [(UInt64, String)] = [(100_000, "សែន"), (10_000, "ម៉ឺន"), (1_000, "ពាន់"), (100, "រយ")]
        for (size, name) in places where remainder >= size {
            parts.append(units[Int(remainder / size)] + name)
            remainder %= size
        }
        if remainder >= 10 {
            parts.append(tens[Int(remainder / 10)])
            remainder %= 10
        }
        if remainder > 0 { parts.append(units[Int(remainder)]) }
        return parts.joined()
    }
    
    /// An amount of money in words: riel are whole (រៀល), dollars have
    /// cents (ដុល្លារ … សេន). Other currencies use the amount in words with
    /// the currency's Khmer name.
    static func moneyWords(for amount: Double, currency: Currency) -> String? {
        switch currency.code {
            case "KHR":
                return words(for: amount.rounded(), fractionDigits: 0).map { $0 + "រៀល" }
            case "USD":
                guard amount.isFinite, abs(amount) < 1e13 else { return nil }
                let totalCents = UInt64((abs(amount) * 100).rounded())
                let (dollars, cents) = (totalCents / 100, totalCents % 100)
                var text = (amount < 0 && totalCents > 0 ? "ដក" : "") + words(forWhole: dollars) + "ដុល្លារ"
                if cents > 0 { text += words(forWhole: cents) + "សេន" }
                return text
            default:
                return words(for: amount, fractionDigits: currency.fractionDigits).map { $0 + currency.khmerName }
        }
    }
}
