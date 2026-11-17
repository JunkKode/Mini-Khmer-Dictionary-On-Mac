//
//  FormulaLexer.swift
//  Mini Khmer Dictionary
//

import Foundation

enum FormulaOperator: Equatable {
    case plus, minus, times, divide, power, percent, concat
    case equal, notEqual, less, lessOrEqual, greater, greaterOrEqual

    /// How the operator is written back out.
    var symbol: String {
        switch self {
        case .plus: "+"
        case .minus: "-"
        case .times: "*"
        case .divide: "/"
        case .power: "^"
        case .percent: "%"
        case .concat: "&"
        case .equal: "="
        case .notEqual: "<>"
        case .less: "<"
        case .lessOrEqual: "<="
        case .greater: ">"
        case .greaterOrEqual: ">="
        }
    }
}

struct FormulaToken: Equatable {
    enum Kind: Equatable {
        /// The `=` that marks the input as a spreadsheet-style formula.
        case formulaPrefix
        case number(Double)
        /// A quoted string. `terminated` is false while the closing quote is
        /// still missing.
        case text(String, terminated: Bool)
        case identifier(String)
        case op(FormulaOperator)
        case leftParen
        case rightParen
        /// `,` or `;` between function arguments.
        case separator
        /// `:` between the corners of a cell range, `A1:B5`.
        case colon
        /// A character the language doesn't use. Kept so the editor can still
        /// colour everything around it.
        case invalid(String)
    }

    let kind: Kind
    /// UTF-16 offsets, which is what `NSTextView` ranges use.
    let range: Range<Int>
}

/// Splits formula source into tokens.
///
/// Scanning never fails: anything unrecognised becomes an `.invalid` token, so
/// the same pass serves both the parser (which rejects those) and the syntax
/// highlighter (which just colours them).
enum FormulaLexer {
    static func tokenize(_ source: String) -> [FormulaToken] {
        let units = Array(source.utf16)
        var tokens: [FormulaToken] = []
        var index = 0

        func peek(_ offset: Int = 0) -> UInt16? {
            let position = index + offset
            return position < units.count ? units[position] : nil
        }

        while index < units.count {
            let start = index
            let unit = units[index]

            if isWhitespace(unit) {
                index += 1
                continue
            }

            // A leading "=" only marks the input as a formula.
            if unit == eq, tokens.isEmpty {
                index += 1
                tokens.append(FormulaToken(kind: .formulaPrefix, range: start..<index))
                continue
            }

            if digitValue(unit) != nil || (unit == dot && peek(1).flatMap({ digitValue($0) }) != nil) {
                var literal = ""
                while let next = peek(), let digit = digitValue(next) {
                    literal.append(Character(String(digit)))
                    index += 1
                }
                if peek() == dot {
                    literal.append(".")
                    index += 1
                    while let next = peek(), let digit = digitValue(next) {
                        literal.append(Character(String(digit)))
                        index += 1
                    }
                }
                // Exponent: 1.5E+20, 2e-3. Only when digits follow, so `2E`
                // stays a number followed by a name and reports a clear error.
                if let marker = peek(), marker == upperE || marker == lowerE {
                    var lookahead = 1
                    if let sign = peek(1), sign == plus || sign == minus { lookahead = 2 }
                    if peek(lookahead).flatMap({ digitValue($0) }) != nil {
                        literal.append("e")
                        if lookahead == 2 { literal.append(peek(1) == minus ? "-" : "+") }
                        index += lookahead
                        while let next = peek(), let digit = digitValue(next) {
                            literal.append(Character(String(digit)))
                            index += 1
                        }
                    }
                }
                let value = Double(literal) ?? .nan
                tokens.append(FormulaToken(kind: .number(value), range: start..<index))
                continue
            }

            if isIdentifierStart(unit) {
                while let next = peek(), isIdentifierPart(next) { index += 1 }
                let name = String(utf16CodeUnits: Array(units[start..<index]), count: index - start)
                tokens.append(FormulaToken(kind: .identifier(name), range: start..<index))
                continue
            }

            if unit == quote || unit == leftCurlyQuote || unit == rightCurlyQuote {
                index += 1
                var content: [UInt16] = []
                var terminated = false
                while let next = peek() {
                    if next == quote || next == rightCurlyQuote || next == leftCurlyQuote {
                        // "" inside a string is an escaped quote.
                        if next == quote, peek(1) == quote {
                            content.append(quote)
                            index += 2
                            continue
                        }
                        index += 1
                        terminated = true
                        break
                    }
                    content.append(next)
                    index += 1
                }
                let text = String(utf16CodeUnits: content, count: content.count)
                tokens.append(FormulaToken(kind: .text(text, terminated: terminated), range: start..<index))
                continue
            }

            index += 1
            let kind: FormulaToken.Kind
            switch unit {
            case plus: kind = .op(.plus)
            case minus, unicodeMinus, enDash: kind = .op(.minus)
            case star, multiplySign, dotOperator: kind = .op(.times)
            case slash, divideSign: kind = .op(.divide)
            case caret: kind = .op(.power)
            case percentSign: kind = .op(.percent)
            case ampersand: kind = .op(.concat)
            case leftParenUnit: kind = .leftParen
            case rightParenUnit: kind = .rightParen
            case comma, semicolon: kind = .separator
            case colonUnit: kind = .colon
            case notEqualSign: kind = .op(.notEqual)
            case lessOrEqualSign: kind = .op(.lessOrEqual)
            case greaterOrEqualSign: kind = .op(.greaterOrEqual)
            case eq:
                if peek() == eq { index += 1 }  // tolerate ==
                kind = .op(.equal)
            case bang where peek() == eq:
                index += 1
                kind = .op(.notEqual)
            case less:
                if peek() == eq { index += 1; kind = .op(.lessOrEqual) }
                else if peek() == greater { index += 1; kind = .op(.notEqual) }
                else { kind = .op(.less) }
            case greater:
                if peek() == eq { index += 1; kind = .op(.greaterOrEqual) }
                else { kind = .op(.greater) }
            default:
                // Keep surrogate pairs together so the message shows the whole
                // character.
                if UTF16.isLeadSurrogate(unit), let trail = peek(), UTF16.isTrailSurrogate(trail) {
                    index += 1
                }
                let text = String(utf16CodeUnits: Array(units[start..<index]), count: index - start)
                kind = .invalid(text)
            }
            tokens.append(FormulaToken(kind: kind, range: start..<index))
        }
        return tokens
    }

    // MARK: - Character classes

    private static let eq = UInt16(UInt8(ascii: "="))
    private static let dot = UInt16(UInt8(ascii: "."))
    private static let plus = UInt16(UInt8(ascii: "+"))
    private static let minus = UInt16(UInt8(ascii: "-"))
    private static let star = UInt16(UInt8(ascii: "*"))
    private static let slash = UInt16(UInt8(ascii: "/"))
    private static let caret = UInt16(UInt8(ascii: "^"))
    private static let percentSign = UInt16(UInt8(ascii: "%"))
    private static let ampersand = UInt16(UInt8(ascii: "&"))
    private static let leftParenUnit = UInt16(UInt8(ascii: "("))
    private static let rightParenUnit = UInt16(UInt8(ascii: ")"))
    private static let comma = UInt16(UInt8(ascii: ","))
    private static let semicolon = UInt16(UInt8(ascii: ";"))
    private static let colonUnit = UInt16(UInt8(ascii: ":"))
    private static let less = UInt16(UInt8(ascii: "<"))
    private static let greater = UInt16(UInt8(ascii: ">"))
    private static let bang = UInt16(UInt8(ascii: "!"))
    private static let quote = UInt16(UInt8(ascii: "\""))
    private static let upperE = UInt16(UInt8(ascii: "E"))
    private static let lowerE = UInt16(UInt8(ascii: "e"))
    private static let underscore = UInt16(UInt8(ascii: "_"))
    private static let unicodeMinus: UInt16 = 0x2212      // −
    private static let enDash: UInt16 = 0x2013            // –
    private static let multiplySign: UInt16 = 0x00D7      // ×
    private static let dotOperator: UInt16 = 0x22C5       // ⋅
    private static let divideSign: UInt16 = 0x00F7        // ÷
    private static let notEqualSign: UInt16 = 0x2260      // ≠
    private static let lessOrEqualSign: UInt16 = 0x2264   // ≤
    private static let greaterOrEqualSign: UInt16 = 0x2265 // ≥
    private static let leftCurlyQuote: UInt16 = 0x201C    // “
    private static let rightCurlyQuote: UInt16 = 0x201D   // ”

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xA0
    }

    /// ASCII digits, plus Khmer digits ០–៩ so numbers can be typed on a Khmer
    /// keyboard.
    static func digitValue(_ unit: UInt16) -> Int? {
        switch unit {
        case 0x30...0x39: Int(unit - 0x30)
        case 0x17E0...0x17E9: Int(unit - 0x17E0)
        default: nil
        }
    }

    private static func isLetter(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
    }

    private static func isIdentifierStart(_ unit: UInt16) -> Bool {
        isLetter(unit) || unit == underscore
    }

    private static func isIdentifierPart(_ unit: UInt16) -> Bool {
        isLetter(unit) || unit == underscore || (unit >= 0x30 && unit <= 0x39) || unit == dot
    }
}
