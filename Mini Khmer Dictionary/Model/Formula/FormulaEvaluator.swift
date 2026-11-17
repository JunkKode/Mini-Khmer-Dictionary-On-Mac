//
//  FormulaEvaluator.swift
//  Mini Khmer Dictionary
//

import Foundation

/// Walks a `FormulaExpression` and produces a value. No code is ever executed
/// dynamically: every operator is handled here, and every call goes through
/// the registry.
struct FormulaEvaluator {
    let functions: FormulaFunctionRegistry
    var cells: FormulaCells?

    /// Larger ranges are refused rather than walked.
    static let maximumRangeSize = 10_000

    func evaluate(_ expression: FormulaExpression) throws -> FormulaValue {
        let value = try value(of: expression)
        switch value {
        case .number(let number): return .number(try finite(number))
        case .percent(let fraction): return .percent(try finite(fraction))
        default: return value
        }
    }

    private func value(of expression: FormulaExpression) throws -> FormulaValue {
        switch expression {
        case .number(let value):
            return .number(value)
        case .text(let text):
            return .text(text)
        case .boolean(let flag):
            return .boolean(flag)
        case .negate(let operand):
            let operandValue = try value(of: operand)
            if case .percent(let fraction) = operandValue { return .percent(-fraction) }
            return .number(-(try finite(operandValue.asNumber())))
        case .percent(let operand):
            return .percent(try number(operand) / 100)
        case .call(let name, let arguments, let range):
            return try call(name, arguments, range)
        case .binary(let op, let left, let right):
            return try binary(op, left, right)
        case .reference(let address, let range):
            return try cellValue(address, range: range) ?? .number(0)  // an empty cell counts as 0
        case .cellRange(let start, let end, let range):
            throw FormulaError(
                .value,
                "A range like \(start.name):\(end.name) needs a function around it, e.g. SUM(\(start.name):\(end.name)).",
                range: range
            )
        }
    }

    // MARK: - Cells

    private func requireCells(_ address: CellAddress, range: Range<Int>) throws -> FormulaCells {
        guard let cells else {
            throw FormulaError(.reference, "Cell references like \(address.name) only work in Grid mode.", range: range)
        }
        guard cells.contains(address) else {
            throw FormulaError(.reference, "There's no cell \(address.name). The grid is \(cells.extent).", range: range)
        }
        return cells
    }

    private func cellValue(_ address: CellAddress, range: Range<Int>) throws -> FormulaValue? {
        let cells = try requireCells(address, range: range)
        do {
            return try cells.value(address)
        } catch var error as FormulaError {
            error.range = range
            throw error
        }
    }

    /// The filled cells of a range; empty ones are skipped, as in a spreadsheet.
    private func rangeValues(_ start: CellAddress, _ end: CellAddress, range: Range<Int>) throws -> [FormulaValue] {
        _ = try requireCells(start, range: range)
        _ = try requireCells(end, range: range)
        let addresses = CellAddress.range(start, end)
        guard addresses.count <= Self.maximumRangeSize else {
            throw FormulaError(.reference, "That range is too large.", range: range)
        }
        return try addresses.compactMap { try cellValue($0, range: range) }
    }

    private func number(_ expression: FormulaExpression) throws -> Double {
        try finite(value(of: expression).asNumber())
    }

    private func finite(_ value: Double) throws -> Double {
        guard value.isFinite else {
            throw FormulaError(.number, value.isNaN ? "The result isn't a number." : "The result is too large to show.")
        }
        return value == 0 ? 0 : value  // no "-0"
    }

    // MARK: - Operators

    private func binary(_ op: FormulaOperator, _ left: FormulaExpression, _ right: FormulaExpression) throws -> FormulaValue {
        switch op {
        case .plus, .minus:
            let lhs = try value(of: left)
            // `a + b%` and `a - b%` adjust a by b percent of itself.
            if case .percent(let inner) = right, case .number(let base) = lhs {
                let change = base * (try number(inner)) / 100
                return .number(try finite(op == .plus ? base + change : base - change))
            }
            let rhs = try value(of: right)
            return try addOrSubtract(op, lhs, rhs)

        case .times:
            return .number(try finite(number(left) * number(right)))

        case .divide:
            let dividend = try number(left), divisor = try number(right)
            guard divisor != 0 else {
                throw FormulaError(.divisionByZero, "Division by zero.")
            }
            return .number(try finite(dividend / divisor))

        case .power:
            return .number(try finite(FormulaArithmetic.power(number(left), number(right))))

        case .concat:
            return .text(try value(of: left).asText + value(of: right).asText)

        case .equal, .notEqual, .less, .lessOrEqual, .greater, .greaterOrEqual:
            return .boolean(try compare(op, value(of: left), value(of: right)))

        case .percent:
            preconditionFailure("% is postfix and never parsed as a binary operator")
        }
    }

    /// Dates shift by whole days; the difference of two dates is a day count.
    private func addOrSubtract(_ op: FormulaOperator, _ lhs: FormulaValue, _ rhs: FormulaValue) throws -> FormulaValue {
        let sign: Double = op == .plus ? 1 : -1
        switch (lhs, rhs) {
        case (.date(let date), .date):
            guard op == .minus else { break }
            return .number(Double(FormulaDate.serial(of: date)) - (try rhs.asNumber()))
        case (.date(let date), _):
            let days = try rhs.asNumber()
            return .date(try FormulaDate.date(fromSerial: Double(FormulaDate.serial(of: date)) + sign * days))
        case (_, .date(let date)) where op == .plus:
            let days = try lhs.asNumber()
            return .date(try FormulaDate.date(fromSerial: Double(FormulaDate.serial(of: date)) + days))
        case (.percent(let a), .percent(let b)):
            // 50% + 10% is 60%, not 50% increased by a tenth.
            return .percent(try finite(a + sign * b))
        default:
            break
        }
        return .number(try finite(lhs.asNumber() + sign * rhs.asNumber()))
    }

    private func compare(_ op: FormulaOperator, _ lhs: FormulaValue, _ rhs: FormulaValue) throws -> Bool {
        let order: ComparisonResult
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):
            order = a.caseInsensitiveCompare(b)
        case (.text, _), (_, .text):
            // Spreadsheets never consider text equal to a number.
            switch op {
            case .equal: return false
            case .notEqual: return true
            default:
                throw FormulaError(.value, "Text can't be compared with a \(lhs.typeName == "text" ? rhs.typeName : lhs.typeName) using \(op.symbol).")
            }
        default:
            let a = try lhs.asNumber(), b = try rhs.asNumber()
            order = a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
        }
        switch op {
        case .equal: return order == .orderedSame
        case .notEqual: return order != .orderedSame
        case .less: return order == .orderedAscending
        case .lessOrEqual: return order != .orderedDescending
        case .greater: return order == .orderedDescending
        case .greaterOrEqual: return order != .orderedAscending
        default: return false
        }
    }

    // MARK: - Calls

    private func call(_ name: String, _ arguments: [FormulaExpression], _ range: Range<Int>) throws -> FormulaValue {
        guard let function = functions.function(named: name) else {
            var message = "There's no function called \(name)."
            if let guess = functions.closestName(to: name) {
                message += " Did you mean \(guess)?"
            }
            throw FormulaError(.unknownName, message, range: range)
        }

        let count = arguments.count
        if count < function.minimumArguments || function.maximumArguments.map({ count > $0 }) == true {
            throw FormulaError(.argumentCount, arityMessage(function, given: count), range: range)
        }

        // A range becomes one argument per filled cell, so SUM(A1:A3) is
        // SUM(A1, A2, A3). Only functions that take any number of values can
        // accept one.
        var thunks: [() throws -> FormulaValue] = []
        var fromRange: [Bool] = []
        for argument in arguments {
            if case .cellRange(let start, let end, let argumentRange) = argument {
                guard function.isVariadic else {
                    throw FormulaError(
                        .value,
                        "\(function.name) takes single values, not a range like \(start.name):\(end.name).",
                        range: argumentRange
                    )
                }
                for value in try rangeValues(start, end, range: argumentRange) {
                    thunks.append { value }
                    fromRange.append(true)
                }
            } else {
                thunks.append { try self.value(of: argument) }
                fromRange.append(false)
            }
        }
        do {
            return try function.evaluate(FormulaArguments(functionName: function.name, thunks: thunks, fromRange: fromRange))
        } catch var error as FormulaError {
            // Point at the call when the function itself didn't say where.
            if error.range == nil { error.range = range }
            throw error
        }
    }

    private func arityMessage(_ function: FormulaFunction, given: Int) -> String {
        let expected: String
        switch (function.minimumArguments, function.maximumArguments) {
        case (0, 0?):
            expected = "takes no arguments"
        case (let low, let high?) where low == high:
            expected = "needs \(low) argument\(low == 1 ? "" : "s")"
        case (let low, let high?):
            expected = "needs \(low) to \(high) arguments"
        case (let low, nil):
            expected = "needs at least \(low) argument\(low == 1 ? "" : "s")"
        }
        return "\(function.name) \(expected), but \(given == 0 ? "none were" : given == 1 ? "1 was" : "\(given) were") given. Usage: \(function.signature)"
    }
}
