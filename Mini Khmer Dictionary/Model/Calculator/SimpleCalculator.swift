//
//  SimpleCalculator.swift
//  Mini Khmer Dictionary
//

import Foundation

/// The keypad calculator's state machine. It builds an expression string in
/// formula syntax and hands it to `FormulaEngine`, so precedence, brackets and
/// percentages behave exactly as they do in the Smart calculator.
///
/// Foundation-only and a value type, so every key sequence is easy to test.
struct SimpleCalculator: Equatable {
    enum Operator: String, CaseIterable {
        case add = "+", subtract = "-", multiply = "*", divide = "/", power = "^"
    }
    
    enum Key: Hashable {
        case digit(Int)
        case decimal
        case op(Operator)
        case percent
        case toggleSign
        case openParen
        case closeParen
        case backspace
        case clear
        case equals
    }
    
    /// A finished `=`: what was entered and what it came to.
    struct Evaluation: Equatable {
        let expression: String
        let value: FormulaValue
    }
    
    /// The expression being typed, in formula syntax (`1500-15%`).
    private(set) var expression = ""
    /// After `=`: the expression that produced the number now in `expression`.
    private(set) var evaluatedExpression: String?
    /// After a failed `=`: why.
    private(set) var error: FormulaError?
    
    /// Digits allowed in one number; doubles can't hold more faithfully.
    static let maximumDigits = 15
    
    var justEvaluated: Bool { evaluatedExpression != nil }
    
    /// What the expression currently comes to, as if `=` were pressed now.
    var preview: FormulaCalculation {
        let source = completedSource
        guard !source.isEmpty else { return .empty }
        return engine.calculate(source)
    }
    
    /// The expression with anything dangling dropped and brackets closed:
    /// `1234.5*(2+` → `1234.5*(2)`.
    private var completedSource: String {
        var source = expression
        while let end = source.last, Self.isOperator(end) || end == "(" { source.removeLast() }
        return Self.closingBrackets(source)
    }
    
    private var engine: FormulaEngine { FormulaEngine() }
    
    static func == (lhs: SimpleCalculator, rhs: SimpleCalculator) -> Bool {
        lhs.expression == rhs.expression && lhs.evaluatedExpression == rhs.evaluatedExpression && lhs.error == rhs.error
    }
    
    // MARK: - Input
    
    /// Applies one key. Returns the evaluation when the key was a successful `=`.
    @discardableResult
    mutating func press(_ key: Key) -> Evaluation? {
        error = nil
        switch key {
            case .digit(let digit): appendDigit(digit)
            case .decimal: appendDecimal()
            case .op(let op): appendOperator(op)
            case .percent: appendPercent()
            case .toggleSign: toggleSign()
            case .openParen: appendOpenParen()
            case .closeParen: appendCloseParen()
            case .backspace: backspace()
            case .clear: self = SimpleCalculator()
            case .equals: return evaluate()
        }
        return nil
    }
    
    /// Replaces everything with `text`, e.g. a history item or the clipboard.
    /// Returns false when `text` isn't something the keypad could have typed.
    @discardableResult
    mutating func load(_ text: String) -> Bool {
        let cleaned = Self.sanitized(text)
        guard !cleaned.isEmpty else { return false }
        self = SimpleCalculator()
        expression = cleaned
        return true
    }
    
    /// Whether `text` only uses what the keypad offers.
    static func canLoad(_ text: String) -> Bool {
        !sanitized(text).isEmpty
    }
    
    private static func sanitized(_ text: String) -> String {
        var source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.hasPrefix("=") { source.removeFirst() }
        var result = ""
        for character in source {
            switch character {
                case " ", ",": continue  // thousands separators from a pasted number
                case "×": result.append("*")
                case "÷": result.append("/")
                case "−", "–": result.append("-")
                case "0"..."9", ".", "+", "-", "*", "/", "^", "%", "(", ")", "E", "e": result.append(character)
                default: return ""
            }
        }
        return result
    }
    
    // MARK: - Keys
    
    private var last: Character? { expression.last }
    
    private var lastIsValue: Bool {
        guard let last else { return false }
        return last.isNumber || last == ")" || last == "%" || last == "."
    }
    
    /// The digits (and point) at the end of the expression.
    private var trailingNumber: String {
        String(expression.reversed().prefix { $0.isNumber || $0 == "." }.reversed())
    }
    
    private mutating func startOverIfEvaluated() {
        if justEvaluated {
            expression = ""
            evaluatedExpression = nil
        }
    }
    
    private mutating func continueFromResult() {
        evaluatedExpression = nil
    }
    
    private mutating func appendDigit(_ digit: Int) {
        startOverIfEvaluated()
        if last == ")" || last == "%" { expression += "*" }
        let number = trailingNumber
        if number == "0" {
            expression.removeLast()  // 05 → 5
        } else if number.filter(\.isNumber).count >= Self.maximumDigits {
            return
        }
        expression += String(digit)
    }
    
    private mutating func appendDecimal() {
        startOverIfEvaluated()
        if trailingNumber.contains(".") { return }
        if last == ")" || last == "%" { expression += "*" }
        if trailingNumber.isEmpty { expression += "0" }
        expression += "."
    }
    
    private mutating func appendOperator(_ op: Operator) {
        continueFromResult()
        if last == "." { expression.removeLast() }
        guard let last else {
            // Nothing yet: a minus starts a negative number, anything else
            // works on zero.
            expression = op == .subtract ? "-" : "0" + op.rawValue
            return
        }
        if last == "(" {
            if op == .subtract { expression += "-" }
            return
        }
        if Self.isOperator(last) {
            // `5 × −` is a negative operand in progress; allow it, otherwise
            // the new operator replaces the old one(s).
            if op == .subtract, last != "-", last != "+" {
                expression += "-"
                return
            }
            while let end = expression.last, Self.isOperator(end) { expression.removeLast() }
            if expression.isEmpty || expression.last == "(" {
                if op == .subtract { expression += "-" }
                return
            }
        }
        expression += op.rawValue
    }
    
    private mutating func appendPercent() {
        continueFromResult()
        guard let last, last.isNumber || last == ")" else { return }
        expression += "%"
    }
    
    private mutating func appendOpenParen() {
        startOverIfEvaluated()
        if last == "." { expression.removeLast() }
        if lastIsValue { expression += "*" }
        expression += "("
    }
    
    private mutating func appendCloseParen() {
        continueFromResult()
        let open = expression.filter { $0 == "(" }.count
        let closed = expression.filter { $0 == ")" }.count
        guard open > closed, lastIsValue else { return }
        if last == "." { expression.removeLast() }
        expression += ")"
    }
    
    private mutating func backspace() {
        continueFromResult()
        guard !expression.isEmpty else { return }
        expression.removeLast()
        // Don't leave half an exponent behind (1.5E+2 → 1.5).
        while let end = expression.last, end == "E" || end == "e" || ((end == "+" || end == "-") && expression.dropLast().last.map { $0 == "E" || $0 == "e" } == true) {
            expression.removeLast()
        }
    }
    
    /// ± flips the sign of the last number or bracketed group.
    private mutating func toggleSign() {
        continueFromResult()
        guard let start = operandStart() else {
            // Nothing to negate yet: start a negative number.
            if last == nil || last == "(" || last.map({ Self.isOperator($0) }) == true, last != "-" {
                expression += "-"
            }
            return
        }
        let before = start > expression.startIndex ? expression[expression.index(before: start)] : nil
        let beforeBefore: Character? = {
            guard before != nil else { return nil }
            let index = expression.index(before: start)
            return index > expression.startIndex ? expression[expression.index(before: index)] : nil
        }()
        let unaryContext = beforeBefore == nil || beforeBefore == "(" || beforeBefore.map({ Self.isOperator($0) }) == true
        
        switch before {
            case "-" where unaryContext:
                expression.remove(at: expression.index(before: start))      // −5 → 5
            case "-":
                expression.replaceSubrange(expression.index(before: start)...expression.index(before: start), with: "+")  // a−5 → a+5
            case "+" where !unaryContext:
                expression.replaceSubrange(expression.index(before: start)...expression.index(before: start), with: "-")  // a+5 → a−5
            default:
                expression.insert("-", at: start)                             // 5 → −5
        }
    }
    
    /// Where the last operand begins: a number (with any `%`) or a bracketed
    /// group.
    private func operandStart() -> String.Index? {
        var index = expression.endIndex
        while index > expression.startIndex, expression[expression.index(before: index)] == "%" {
            index = expression.index(before: index)
        }
        guard index > expression.startIndex else { return nil }
        let previous = expression[expression.index(before: index)]
        
        if previous == ")" {
            var depth = 0
            var cursor = index
            while cursor > expression.startIndex {
                cursor = expression.index(before: cursor)
                if expression[cursor] == ")" { depth += 1 }
                if expression[cursor] == "(" {
                    depth -= 1
                    if depth == 0 { return cursor }
                }
            }
            return nil
        }
        
        guard previous.isNumber || previous == "." else { return nil }
        var cursor = index
        while cursor > expression.startIndex {
            let before = expression[expression.index(before: cursor)]
            let isExponentSign = (before == "+" || before == "-") && cursor > expression.index(after: expression.startIndex)
            && ["E", "e"].contains(expression[expression.index(cursor, offsetBy: -2)])
            guard before.isNumber || before == "." || before == "E" || before == "e" || isExponentSign else { break }
            cursor = expression.index(before: cursor)
        }
        return cursor
    }
    
    private mutating func evaluate() -> Evaluation? {
        guard !expression.isEmpty, !justEvaluated else { return nil }
        let source = completedSource
        guard !source.isEmpty else { return nil }
        
        switch engine.calculate(source) {
            case .value(let value, _):
                evaluatedExpression = source
                expression = FormulaFormatter.plain(value)
                return Evaluation(expression: source, value: value)
            case .failure(let failure):
                error = failure
                return nil
            case .empty:
                return nil
        }
    }
    
    // MARK: - Helpers
    
    private static func isOperator(_ character: Character) -> Bool {
        Operator(rawValue: String(character)) != nil
    }
    
    /// `(1+2` → `(1+2)`, so a preview can be shown before the user closes it.
    static func closingBrackets(_ source: String) -> String {
        let missing = source.filter { $0 == "(" }.count - source.filter { $0 == ")" }.count
        return missing > 0 ? source + String(repeating: ")", count: missing) : source
    }
    
    /// The expression made readable: `1,500 − 15% × (2 + 3)`.
    static func displayText(_ source: String) -> String {
        var output = ""
        var previous: FormulaToken.Kind?
        let ns = source as NSString
        for token in FormulaLexer.tokenize(source) {
            let raw = ns.substring(with: NSRange(location: token.range.lowerBound, length: token.range.count))
            switch token.kind {
                case .number:
                    output += groupedInteger(raw)
                case .op(let op):
                    let isUnary: Bool = {
                        switch previous {
                            case nil, .leftParen?, .op(.plus)?, .op(.minus)?, .op(.times)?, .op(.divide)?, .op(.power)?: true
                            default: false
                        }
                    }()
                    switch op {
                        case .percent: output += "%"
                        case .minus where isUnary: output += "−"
                        case .minus: output += " − "
                        case .plus: output += " + "
                        case .times: output += " × "
                        case .divide: output += " ÷ "
                        case .power: output += "^"
                        default: output += raw
                    }
                default:
                    output += raw
            }
            previous = token.kind
        }
        return output
    }
    
    /// Adds thousands separators to the whole part of a number as typed,
    /// keeping the decimals exactly as entered (`1234.50` → `1,234.50`).
    private static func groupedInteger(_ raw: String) -> String {
        guard !raw.contains("e"), !raw.contains("E") else { return raw }
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = String(parts.first ?? "")
        var grouped = ""
        for (offset, character) in whole.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        let integer = String(grouped.reversed())
        return parts.count > 1 ? integer + "." + parts[1] : integer
    }
}
