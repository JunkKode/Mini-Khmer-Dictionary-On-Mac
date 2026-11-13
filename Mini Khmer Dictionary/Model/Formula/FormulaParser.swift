//
//  FormulaParser.swift
//  Mini Khmer Dictionary
//

import Foundation

/// A parsed formula. The parser knows nothing about what functions exist; calls
/// are resolved against a `FormulaFunctionRegistry` at evaluation time.
indirect enum FormulaExpression: Equatable {
    case number(Double)
    case text(String)
    case boolean(Bool)
    case negate(FormulaExpression)
    case binary(FormulaOperator, FormulaExpression, FormulaExpression)
    /// Postfix `%`. On its own it divides by 100; on the right of `+` or `-`
    /// it means "percent of the left side" (`1500 - 15%` is 1275).
    case percent(FormulaExpression)
    /// `range` covers the function name, for error reporting.
    case call(name: String, arguments: [FormulaExpression], range: Range<Int>)
}

/// Recursive-descent parser. Precedence, loosest first:
///
///     comparison   =  <>  <  >  <=  >=
///     concat       &
///     additive     +  -
///     multiplicative  *  /
///     unary        -x  +x          (so -2^2 is -4, as in mathematics)
///     power        ^               (right-associative: 2^3^2 is 2^9)
///     postfix      x%
///     primary      number  "text"  TRUE  NAME(args)  (expr)
struct FormulaParser {
    /// Deeper nesting than this is almost certainly a mistake, and refusing it
    /// keeps a pathological input from exhausting the stack.
    static let maximumDepth = 64
    static let maximumLength = 2_000

    private let tokens: [FormulaToken]
    private let sourceLength: Int
    private var position = 0
    private var depth = 0

    /// Parses `source`, with or without a leading `=`.
    static func parse(_ source: String) throws -> FormulaExpression {
        let length = source.utf16.count
        guard length <= maximumLength else {
            throw FormulaError(.syntax, "That formula is too long (over \(maximumLength) characters).")
        }
        var parser = FormulaParser(tokens: FormulaLexer.tokenize(source), sourceLength: length)
        return try parser.parseFormula()
    }

    private init(tokens: [FormulaToken], sourceLength: Int) {
        self.tokens = tokens
        self.sourceLength = sourceLength
    }

    // MARK: - Grammar

    private mutating func parseFormula() throws -> FormulaExpression {
        if case .formulaPrefix = current?.kind { position += 1 }
        guard current != nil else {
            throw FormulaError(.incomplete, "Type an expression after “=”.")
        }
        let expression = try parseComparison()
        if let extra = current {
            throw unexpected(extra)
        }
        return expression
    }

    private mutating func parseComparison() throws -> FormulaExpression {
        var left = try parseConcat()
        while let op = currentOperator, [.equal, .notEqual, .less, .lessOrEqual, .greater, .greaterOrEqual].contains(op) {
            position += 1
            left = .binary(op, left, try parseConcat())
        }
        return left
    }

    private mutating func parseConcat() throws -> FormulaExpression {
        var left = try parseAdditive()
        while currentOperator == .concat {
            position += 1
            left = .binary(.concat, left, try parseAdditive())
        }
        return left
    }

    private mutating func parseAdditive() throws -> FormulaExpression {
        var left = try parseMultiplicative()
        while let op = currentOperator, op == .plus || op == .minus {
            position += 1
            left = .binary(op, left, try parseMultiplicative())
        }
        return left
    }

    private mutating func parseMultiplicative() throws -> FormulaExpression {
        var left = try parseUnary()
        while let op = currentOperator, op == .times || op == .divide {
            position += 1
            left = .binary(op, left, try parseUnary())
        }
        return left
    }

    private mutating func parseUnary() throws -> FormulaExpression {
        if let op = currentOperator, op == .minus || op == .plus {
            position += 1
            try descend()
            defer { depth -= 1 }
            let operand = try parseUnary()
            return op == .minus ? .negate(operand) : operand
        }
        return try parsePower()
    }

    private mutating func parsePower() throws -> FormulaExpression {
        let base = try parsePostfix()
        guard currentOperator == .power else { return base }
        position += 1
        try descend()
        defer { depth -= 1 }
        // The exponent may itself be negative or another power: 2^-1, 2^3^2.
        return .binary(.power, base, try parseUnary())
    }

    private mutating func parsePostfix() throws -> FormulaExpression {
        var expression = try parsePrimary()
        while currentOperator == .percent {
            position += 1
            expression = .percent(expression)
        }
        return expression
    }

    private mutating func parsePrimary() throws -> FormulaExpression {
        guard let token = current else {
            throw FormulaError(.incomplete, "The formula ends too early.", range: sourceLength..<sourceLength)
        }

        switch token.kind {
        case .number(let value):
            position += 1
            guard value.isFinite else {
                throw FormulaError(.number, "That number is too large.", range: token.range)
            }
            return .number(value)

        case .text(let text, let terminated):
            position += 1
            guard terminated else {
                throw FormulaError(.incomplete, "The text is missing its closing quote.", range: token.range)
            }
            return .text(text)

        case .identifier(let name):
            position += 1
            if case .leftParen = current?.kind {
                return try parseCall(name: name, nameRange: token.range)
            }
            switch name.uppercased() {
            case "TRUE": return .boolean(true)
            case "FALSE": return .boolean(false)
            default:
                throw FormulaError(
                    .unknownName,
                    "“\(name)” isn't a number or a function. Functions need brackets, like \(name.uppercased())().",
                    range: token.range
                )
            }

        case .leftParen:
            position += 1
            try descend()
            defer { depth -= 1 }
            let inner = try parseComparison()
            try expectClosingParen(openedAt: token.range)
            return inner

        default:
            throw unexpected(token)
        }
    }

    private mutating func parseCall(name: String, nameRange: Range<Int>) throws -> FormulaExpression {
        let openParen = current!.range
        position += 1  // (
        try descend()
        defer { depth -= 1 }

        var arguments: [FormulaExpression] = []
        if case .rightParen = current?.kind {
            position += 1
            return .call(name: name.uppercased(), arguments: [], range: nameRange)
        }
        while true {
            if case .separator = current?.kind {
                throw FormulaError(.syntax, "An argument is missing in \(name.uppercased())().", range: current!.range)
            }
            arguments.append(try parseComparison())
            if case .separator = current?.kind {
                position += 1
                continue
            }
            try expectClosingParen(openedAt: openParen)
            return .call(name: name.uppercased(), arguments: arguments, range: nameRange)
        }
    }

    // MARK: - Helpers

    private var current: FormulaToken? {
        position < tokens.count ? tokens[position] : nil
    }

    private var currentOperator: FormulaOperator? {
        if case .op(let op) = current?.kind { return op }
        return nil
    }

    private mutating func descend() throws {
        depth += 1
        if depth > Self.maximumDepth {
            throw FormulaError(.syntax, "The formula is nested too deeply.")
        }
    }

    private mutating func expectClosingParen(openedAt open: Range<Int>) throws {
        guard let token = current else {
            throw FormulaError(.incomplete, "A closing bracket “)” is missing.", range: open)
        }
        guard case .rightParen = token.kind else {
            if case .number = token.kind {
                throw FormulaError(.syntax, "Use a comma between arguments, or an operator between numbers.", range: token.range)
            }
            throw unexpected(token)
        }
        position += 1
    }

    private func unexpected(_ token: FormulaToken) -> FormulaError {
        switch token.kind {
        case .invalid(let text):
            return FormulaError(.syntax, "“\(text)” can't be used in a formula.", range: token.range)
        case .rightParen:
            return FormulaError(.syntax, "There's a “)” without a matching “(”.", range: token.range)
        case .separator:
            return FormulaError(.syntax, "Commas only separate function arguments.", range: token.range)
        case .formulaPrefix:
            return FormulaError(.syntax, "Unexpected “=”.", range: token.range)
        case .op(let op):
            return FormulaError(.syntax, "“\(op.symbol)” is missing a value before it.", range: token.range)
        case .number, .identifier, .text, .leftParen:
            return FormulaError(.syntax, "An operator is missing before this.", range: token.range)
        }
    }
}

// MARK: - Printing

extension FormulaExpression {
    /// The expression written out the way the engine understood it: function
    /// names in capitals, consistent spacing, and only the brackets that
    /// change the meaning.
    var canonicalText: String {
        switch self {
        case .number(let value):
            return FormulaFormatter.plain(value)
        case .text(let text):
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        case .boolean(let flag):
            return flag ? "TRUE" : "FALSE"
        case .negate(let operand):
            return "-" + operand.printed(within: precedence)
        case .percent(let operand):
            return operand.printed(within: precedence) + "%"
        case .call(let name, let arguments, _):
            return name + "(" + arguments.map(\.canonicalText).joined(separator: ", ") + ")"
        case .binary(let op, let left, let right):
            let rightAssociative = op == .power
            let leftText = left.printed(within: precedence, strictly: rightAssociative)
            let rightText = right.printed(within: precedence, strictly: !rightAssociative)
            return op == .power ? "\(leftText)^\(rightText)" : "\(leftText) \(op.symbol) \(rightText)"
        }
    }

    private var precedence: Int {
        switch self {
        case .number, .text, .boolean, .call: 8
        case .percent: 7
        case .negate: 5
        case .binary(let op, _, _):
            switch op {
            case .power: 6
            case .times, .divide: 4
            case .plus, .minus: 3
            case .concat: 2
            default: 1
            }
        }
    }

    private func printed(within parent: Int, strictly: Bool = false) -> String {
        let needsBrackets = strictly ? precedence <= parent : precedence < parent
        return needsBrackets ? "(\(canonicalText))" : canonicalText
    }
}
