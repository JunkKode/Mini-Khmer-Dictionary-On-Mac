//
//  FormulaFunctions.swift
//  Mini Khmer Dictionary
//

import Foundation

/// A built-in function the formula language can call.
///
/// To add one, build a `FormulaFunction` and `register` it — the parser never
/// needs to change, because it only records `NAME(arguments)` and leaves the
/// lookup to evaluation time.
struct FormulaFunction {
    enum Category: String, CaseIterable {
        case math = "Math"
        case percentage = "Percentage"
        case logical = "Logical"
        case text = "Text"
        case date = "Date"
        case khmer = "Khmer"
        case finance = "Money"
    }

    let name: String
    let category: Category
    /// Parameter names for the signature hint, e.g. `["number", "digits"]`.
    let parameters: [String]
    /// When true the last parameter may repeat: `SUM(number1, number2, …)`.
    let isVariadic: Bool
    let minimumArguments: Int
    /// `nil` means no upper limit.
    let maximumArguments: Int?
    let summary: String
    let example: String
    let evaluate: (FormulaArguments) throws -> FormulaValue

    init(
        _ name: String,
        category: Category,
        parameters: [String],
        variadic: Bool = false,
        minimum: Int? = nil,
        maximum: Int?? = nil,
        summary: String,
        example: String,
        evaluate: @escaping (FormulaArguments) throws -> FormulaValue
    ) {
        self.name = name.uppercased()
        self.category = category
        self.parameters = parameters
        self.isVariadic = variadic
        let required = parameters.filter { !$0.hasPrefix("[") }.count
        self.minimumArguments = minimum ?? required
        self.maximumArguments = maximum ?? (variadic ? nil : parameters.count)
        self.summary = summary
        self.example = example
        self.evaluate = evaluate
    }

    /// `ROUND(number, digits)`, `SUM(number1, …)`.
    var signature: String {
        name + "(" + (parameters + (isVariadic ? ["…"] : [])).joined(separator: ", ") + ")"
    }

    /// Index into `parameters` for the argument at `index`, or `nil` when the
    /// function takes no argument there.
    func parameterIndex(forArgument index: Int) -> Int? {
        guard !parameters.isEmpty else { return nil }
        if index < parameters.count { return index }
        return isVariadic ? parameters.count - 1 : nil
    }
}

/// The arguments of one call. Each is evaluated only when asked for, so `IF`
/// can skip the branch it doesn't take (and its division by zero).
struct FormulaArguments {
    let functionName: String
    private let thunks: [() throws -> FormulaValue]
    /// Which arguments came from a cell range rather than being written out.
    private let fromRange: [Bool]

    init(functionName: String, thunks: [() throws -> FormulaValue], fromRange: [Bool]? = nil) {
        self.functionName = functionName
        self.thunks = thunks
        self.fromRange = fromRange ?? Array(repeating: false, count: thunks.count)
    }

    var count: Int { thunks.count }

    func value(_ index: Int) throws -> FormulaValue {
        try thunks[index]()
    }

    func number(_ index: Int) throws -> Double {
        try value(index).asNumber(context: functionName)
    }

    func boolean(_ index: Int) throws -> Bool {
        try value(index).asBoolean(context: functionName)
    }

    func text(_ index: Int) throws -> String {
        try value(index).asText
    }

    /// A rate as a fraction. A percentage is used as it is and a plain number
    /// is read as percentage points, so `15%` and `15` both mean fifteen
    /// percent (and `0.15` means 0.15%).
    func rate(_ index: Int) throws -> Double {
        let raw = try value(index)
        if case .percent(let fraction) = raw { return fraction }
        return try raw.asNumber(context: functionName) / 100
    }

    /// A whole number argument such as ROUND's digits.
    func integer(_ index: Int, name: String) throws -> Int {
        let raw = try number(index)
        guard raw.isFinite, abs(raw) <= 300 else {
            throw FormulaError(.number, "\(functionName)'s \(name) is out of range.")
        }
        return Int(raw.rounded(.towardZero))
    }

    func allValues() throws -> [FormulaValue] {
        try thunks.map { try $0() }
    }

    /// Every argument as a number. Text that came from a range is skipped,
    /// so a column's heading doesn't break SUM(A1:A10).
    func allNumbers() throws -> [Double] {
        try thunks.indices.compactMap { index in
            let value = try thunks[index]()
            if fromRange[index], case .text = value { return nil }
            return try value.asNumber(context: functionName)
        }
    }
}

/// Looks functions up by name.
struct FormulaFunctionRegistry {
    private var functionsByName: [String: FormulaFunction] = [:]

    init(_ functions: [FormulaFunction] = []) {
        functions.forEach { register($0) }
    }

    /// Adds `function`, replacing any existing one with the same name.
    mutating func register(_ function: FormulaFunction) {
        functionsByName[function.name] = function
    }

    func function(named name: String) -> FormulaFunction? {
        functionsByName[name.uppercased()]
    }

    /// Every function, alphabetically.
    var all: [FormulaFunction] {
        functionsByName.values.sorted { $0.name < $1.name }
    }

    /// Functions whose name starts with `prefix`; an exact match comes first.
    func functions(matchingPrefix prefix: String) -> [FormulaFunction] {
        let upper = prefix.uppercased()
        guard !upper.isEmpty else { return [] }
        return all
            .filter { $0.name.hasPrefix(upper) }
            .sorted { ($0.name == upper ? 0 : 1, $0.name) < ($1.name == upper ? 0 : 1, $1.name) }
    }

    /// The closest known name to a misspelt one, for "Did you mean …?".
    func closestName(to name: String) -> String? {
        let upper = name.uppercased()
        let ranked = all
            .map { ($0.name, editDistance(upper, $0.name)) }
            .min { ($0.1, $0.0) < ($1.1, $1.0) }
        guard let ranked, ranked.1 <= max(1, upper.count / 3) else { return nil }
        return ranked.0
    }

    private func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = row
        }
        return previous[b.count]
    }
}

// MARK: - Standard library

extension FormulaFunctionRegistry {
    /// The functions the calculator ships with.
    static let standard = FormulaFunctionRegistry(
        mathFunctions + percentageFunctions + logicalFunctions + otherFunctions + khmerFunctions
    )

    private static let mathFunctions: [FormulaFunction] = [
        FormulaFunction(
            "SUM", category: .math, parameters: ["number1"], variadic: true,
            summary: "Adds all of its arguments.", example: "SUM(100, 200, 300)"
        ) { args in
            .number(try args.allNumbers().reduce(0, +))
        },
        FormulaFunction(
            "AVERAGE", category: .math, parameters: ["number1"], variadic: true,
            summary: "The arithmetic mean of its arguments.", example: "AVERAGE(10, 20, 30)"
        ) { args in
            let numbers = try args.allNumbers()
            guard !numbers.isEmpty else {
                throw FormulaError(.divisionByZero, "AVERAGE has no numbers to average.")
            }
            return .number(numbers.reduce(0, +) / Double(numbers.count))
        },
        FormulaFunction(
            "MIN", category: .math, parameters: ["number1"], variadic: true,
            summary: "The smallest of its arguments.", example: "MIN(10, 50, 100)"
        ) { args in
            .number(try args.allNumbers().min() ?? 0)  // an empty range gives 0
        },
        FormulaFunction(
            "MAX", category: .math, parameters: ["number1"], variadic: true,
            summary: "The largest of its arguments.", example: "MAX(10, 50, 100)"
        ) { args in
            .number(try args.allNumbers().max() ?? 0)
        },
        FormulaFunction(
            "COUNT", category: .math, parameters: ["value1"], variadic: true,
            summary: "How many of its arguments are numbers.", example: "COUNT(1, \"a\", 3)"
        ) { args in
            let numeric = try args.allValues().filter {
                switch $0 {
                case .number, .percent, .date: true
                default: false
                }
            }
            return .number(Double(numeric.count))
        },
        FormulaFunction(
            "ROUND", category: .math, parameters: ["number", "[digits]"],
            summary: "Rounds to a number of decimal places, halves away from zero.", example: "ROUND(123.456, 2)"
        ) { args in
            try FormulaRounding.round(args, rule: .plain)
        },
        FormulaFunction(
            "ROUNDUP", category: .math, parameters: ["number", "[digits]"],
            summary: "Rounds away from zero.", example: "ROUNDUP(3.141, 2)"
        ) { args in
            try FormulaRounding.round(args, rule: .up)
        },
        FormulaFunction(
            "ROUNDDOWN", category: .math, parameters: ["number", "[digits]"],
            summary: "Rounds toward zero.", example: "ROUNDDOWN(3.149, 2)"
        ) { args in
            try FormulaRounding.round(args, rule: .down)
        },
        FormulaFunction(
            "ABS", category: .math, parameters: ["number"],
            summary: "The number without its sign.", example: "ABS(-100)"
        ) { args in
            let value = try args.value(0)
            if case .percent(let fraction) = value { return .percent(abs(fraction)) }
            return .number(abs(try value.asNumber(context: args.functionName)))
        },
        FormulaFunction(
            "POWER", category: .math, parameters: ["number", "power"],
            summary: "Raises a number to a power, like ^.", example: "POWER(2, 10)"
        ) { args in
            .number(try FormulaArithmetic.power(args.number(0), args.number(1)))
        },
        FormulaFunction(
            "SQRT", category: .math, parameters: ["number"],
            summary: "The positive square root.", example: "SQRT(144)"
        ) { args in
            let value = try args.number(0)
            guard value >= 0 else {
                throw FormulaError(.number, "SQRT needs a number that isn't negative.")
            }
            return .number(value.squareRoot())
        },
        FormulaFunction(
            "MOD", category: .math, parameters: ["number", "divisor"],
            summary: "The remainder after division; takes the divisor's sign.", example: "MOD(10, 3)"
        ) { args in
            let number = try args.number(0), divisor = try args.number(1)
            guard divisor != 0 else {
                throw FormulaError(.divisionByZero, "MOD can't divide by zero.")
            }
            return .number(number - divisor * (number / divisor).rounded(.down))
        },
        FormulaFunction(
            "PI", category: .math, parameters: [],
            summary: "π to 15 digits.", example: "PI() * 2^2"
        ) { _ in
            .number(Double.pi)
        },
    ]

    /// Everyday percentage sums. Each rate may be written `15%` or `15`.
    private static let percentageFunctions: [FormulaFunction] = [
        FormulaFunction(
            "PERCENTOF", category: .percentage, parameters: ["rate", "amount"],
            summary: "That percentage of an amount: 15% of 2000 is 300.", example: "PERCENTOF(15%, 2000)"
        ) { args in
            .number(try args.number(1) * args.rate(0))
        },
        FormulaFunction(
            "DISCOUNT", category: .percentage, parameters: ["amount", "rate"],
            summary: "The amount after taking a percentage off.", example: "DISCOUNT(2000, 15%)"
        ) { args in
            let amount = try args.number(0), rate = try args.rate(1)
            guard rate >= 0 else {
                throw FormulaError(.number, "DISCOUNT's rate can't be negative. Use ADDPERCENT to add to an amount.")
            }
            guard rate <= 1 else {
                throw FormulaError(.number, "A discount can't be more than 100%.")
            }
            return .number(amount - amount * rate)
        },
        FormulaFunction(
            "ADDPERCENT", category: .percentage, parameters: ["amount", "rate"],
            summary: "The amount plus a percentage, e.g. tax or markup.", example: "ADDPERCENT(2000, 10%)"
        ) { args in
            let amount = try args.number(0)
            return .number(amount + amount * (try args.rate(1)))
        },
        FormulaFunction(
            "PERCENTAGE", category: .percentage, parameters: ["part", "whole"],
            summary: "What percentage the part is of the whole: 300 of 2000 is 15%.", example: "PERCENTAGE(300, 2000)"
        ) { args in
            let part = try args.number(0), whole = try args.number(1)
            guard whole != 0 else {
                throw FormulaError(.divisionByZero, "PERCENTAGE can't take a percentage of zero.")
            }
            return .percent(part / whole)
        },
        FormulaFunction(
            "PERCENTCHANGE", category: .percentage, parameters: ["old", "new"],
            summary: "How much a value rose or fell, as a percentage of where it started.",
            example: "PERCENTCHANGE(1500, 1800)"
        ) { args in
            let old = try args.number(0), new = try args.number(1)
            guard old != 0 else {
                throw FormulaError(.divisionByZero, "PERCENTCHANGE can't measure a change from zero.")
            }
            return .percent((new - old) / abs(old))
        },
    ]

    private static let logicalFunctions: [FormulaFunction] = [
        FormulaFunction(
            "IF", category: .logical, parameters: ["condition", "value_if_true", "[value_if_false]"],
            summary: "One value when the condition holds, another when it doesn't.",
            example: "IF(100 > 50, \"Pass\", \"Fail\")"
        ) { args in
            if try args.boolean(0) {
                return try args.value(1)
            }
            return args.count > 2 ? try args.value(2) : .boolean(false)
        },
        FormulaFunction(
            "AND", category: .logical, parameters: ["condition1"], variadic: true,
            summary: "TRUE when every condition holds.", example: "AND(5 > 1, 2 < 3)"
        ) { args in
            for index in 0..<args.count {
                if try !args.boolean(index) { return .boolean(false) }
            }
            return .boolean(true)
        },
        FormulaFunction(
            "OR", category: .logical, parameters: ["condition1"], variadic: true,
            summary: "TRUE when any condition holds.", example: "OR(5 > 10, 2 < 3)"
        ) { args in
            for index in 0..<args.count {
                if try args.boolean(index) { return .boolean(true) }
            }
            return .boolean(false)
        },
        FormulaFunction(
            "NOT", category: .logical, parameters: ["condition"],
            summary: "Reverses TRUE and FALSE.", example: "NOT(5 > 10)"
        ) { args in
            .boolean(!(try args.boolean(0)))
        },
    ]

    private static let otherFunctions: [FormulaFunction] = [
        FormulaFunction(
            "CONCAT", category: .text, parameters: ["text1"], variadic: true,
            summary: "Joins its arguments into one piece of text.", example: "CONCAT(\"Total: \", 600)"
        ) { args in
            .text(try args.allValues().map(\.asText).joined())
        },
        FormulaFunction(
            "LEN", category: .text, parameters: ["text"],
            summary: "The number of characters in the text.", example: "LEN(\"hello\")"
        ) { args in
            .number(Double(try args.text(0).count))
        },
        FormulaFunction(
            "TODAY", category: .date, parameters: [],
            summary: "Today's date. Add or subtract days: TODAY() + 30.", example: "TODAY() + 30"
        ) { _ in
            .date(FormulaDate.today())
        },
    ]
}

// MARK: - Numeric helpers

enum FormulaArithmetic {
    static func power(_ base: Double, _ exponent: Double) throws -> Double {
        if base == 0 && exponent < 0 {
            throw FormulaError(.divisionByZero, "Zero can't be raised to a negative power.")
        }
        let result = Foundation.pow(base, exponent)
        guard !result.isNaN else {
            throw FormulaError(.number, "A negative number can't be raised to a fractional power.")
        }
        return result
    }
}

enum FormulaRounding {
    enum Rule { case plain, up, down }

    /// ROUND, ROUNDUP and ROUNDDOWN. A percentage is rounded as it reads, so
    /// `ROUND(PERCENTAGE(1, 3), 2)` is 33.33%, and stays a percentage.
    static func round(_ args: FormulaArguments, rule: Rule) throws -> FormulaValue {
        let value = try args.value(0)
        let digits = args.count > 1 ? try args.integer(1, name: "digits") : 0
        if case .percent(let fraction) = value {
            return .percent(try round(fraction * 100, digits: digits, rule: rule) / 100)
        }
        return .number(try round(value.asNumber(context: args.functionName), digits: digits, rule: rule))
    }

    /// Rounds in decimal rather than binary, so `ROUND(1.005, 2)` is 1.01 the
    /// way a person (and Excel) expects, not 1.00.
    static func round(_ value: Double, digits: Int, rule: Rule) throws -> Double {
        guard value.isFinite else { return value }
        // Swift prints the shortest text that reads back as the same double,
        // which is exactly the decimal the user meant.
        guard var decimal = Decimal(string: "\(abs(value))", locale: Locale(identifier: "en_US_POSIX")) else {
            return value
        }
        var rounded = Decimal()
        let mode: NSDecimalNumber.RoundingMode = switch rule {
        case .plain: .plain
        case .up: .up
        case .down: .down
        }
        NSDecimalRound(&rounded, &decimal, digits, mode)
        let magnitude = NSDecimalNumber(decimal: rounded).doubleValue
        return value < 0 ? -magnitude : magnitude
    }
}
