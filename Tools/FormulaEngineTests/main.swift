//
//  Tests for the formula engine and the keypad calculator.
//
//  Compiled together with Model/Formula/*.swift and
//  Model/Calculator/SimpleCalculator.swift by Tools/test_formula_engine.sh —
//  those files depend on Foundation only, which is what makes this possible.
//

import Foundation

var failures = 0
var passes = 0

func check(_ condition: Bool, _ message: @autoclosure () -> String, line: Int = #line) {
    if condition {
        passes += 1
    } else {
        failures += 1
        print("FAIL (line \(line)): \(message())")
    }
}

let engine = FormulaEngine()

/// The displayed result of `source`, or the error code and message.
func shown(_ source: String) -> String {
    switch engine.calculate(source) {
    case .empty: return "<empty>"
    case .value(let value, _): return FormulaFormatter.display(value)
    case .failure(let error): return "\(error.code) \(error.message)"
    }
}

func expect(_ source: String, _ expected: String, line: Int = #line) {
    let actual = shown(source)
    check(actual == expected, "\(source)  →  \(actual)   (expected \(expected))", line: line)
}

func expectError(_ source: String, _ kind: FormulaError.Kind, line: Int = #line) {
    let result = engine.calculate(source)
    check(result.error?.kind == kind, "\(source)  →  \(shown(source))   (expected \(kind))", line: line)
}

func expectCanonical(_ source: String, _ expected: String, line: Int = #line) {
    guard case .value(_, let expression) = engine.calculate(source) else {
        check(false, "\(source) did not evaluate: \(shown(source))", line: line)
        return
    }
    check(expression == expected, "\(source) printed as \(expression)   (expected \(expected))", line: line)
}

// MARK: - Arithmetic and precedence

expect("100 + 200", "300")
expect("500 * 1.1", "550")
expect("(100 + 200) / 3", "100")
expect("100 + 200 * 3", "700")
expect("(1500 + 2500) / 2", "2,000")
expect("5000 * 0.15", "750")
expect("2 ^ 10", "1,024")
expect("2^3^2", "512")
expect("-2^2", "-4")
expect("(-2)^2", "4")
expect("2^-1", "0.5")
expect("10 - 4 - 3", "3")
expect("100 / 10 / 5", "2")
expect("0.1 + 0.2", "0.3")
expect("1/3", "0.3333333333")
expect("-(-5)", "5")
expect("+5", "5")
expect("3 × 4 ÷ 2 − 1", "5")
expect("1.5e3", "1,500")
expect("១០០ + ២០០", "300")       // Khmer digits
expect(".5 * 4", "2")
expect("1e20", "1E+20")
expect("123456789 * 1000", "123,456,789,000")

// MARK: - Percent

expect("1500 - 15%", "1,275")
expect("200 + 10%", "220")
expect("50%", "0.5")
expect("200 * 10%", "20")
expect("=IF(5000 >= 10000, 10%, 5%)", "0.05")

// MARK: - Functions

expect("=SUM(100, 200, 300)", "600")
expect("=AVERAGE(10, 20, 30)", "20")
expect("=MAX(10, 50, 100)", "100")
expect("=MIN(10, 50, 100)", "10")
expect("=ROUND(123.456, 2)", "123.46")
expect("=ABS(-100)", "100")
expect("=POWER(2, 10)", "1,024")
expect("=COUNT(1, \"a\", 3, TRUE)", "2")
expect("=ROUNDUP(3.141, 2)", "3.15")
expect("=ROUNDDOWN(3.149, 2)", "3.14")
expect("=ROUNDUP(-3.141, 2)", "-3.15")
expect("=ROUNDDOWN(-3.149, 2)", "-3.14")
expect("=ROUND(1.005, 2)", "1.01")
expect("=ROUND(2.5)", "3")
expect("=ROUND(-2.5)", "-3")
expect("=ROUND(1234.5, -2)", "1,200")
expect("=SQRT(144)", "12")
expect("=MOD(10, 3)", "1")
expect("=MOD(-10, 3)", "2")
expect("=MOD(10, -3)", "-2")
expect("=PI()", "3.1415926536")
expect("=CONCAT(\"Total: \", 600)", "Total: 600")
expect("=LEN(\"hello\")", "5")
expect("=\"a\" & \"b\" & 1", "ab1")
expect("sum(1,2)", "3")                 // case-insensitive, no "="
expect("=SUM(1; 2; 3)", "6")            // semicolons separate too

// MARK: - Logic

expect("=IF(100 > 50, \"Pass\", \"Fail\")", "Pass")
expect("=IF(10 > 50, \"Pass\", \"Fail\")", "Fail")
expect("=IF(1 > 2, 5)", "FALSE")
expect("=AND(5 > 1, 2 < 3)", "TRUE")
expect("=AND(5 > 1, 2 > 3)", "FALSE")
expect("=OR(5 > 10, 2 < 3)", "TRUE")
expect("=NOT(5 > 10)", "TRUE")
expect("=1 = 1", "TRUE")
expect("=1 <> 1", "FALSE")
expect("=1 != 2", "TRUE")
expect("=\"abc\" = \"ABC\"", "TRUE")
expect("=1 = \"1\"", "FALSE")
expect("=IF(TRUE, 1, 1/0)", "1")         // the untaken branch never runs

// MARK: - Nesting

expect("=ROUND((1500 + 2500) * 0.15, 2)", "600")
expect("=SUM(100, 200, 300) * 1.1", "660")
expect("=IF(100 > 50, SUM(100, 200), 0)", "300")
expect("=ROUND(125.678 * 1.15, 2)", "144.53")
expect("=MAX(SUM(1, 2), AVERAGE(10, 20), MIN(100, 5))", "15")

// MARK: - Dates

check(engine.calculate("=TODAY() + 30").value.map { if case .date = $0 { true } else { false } } == true, "TODAY()+30 is a date")
expect("=TODAY() - TODAY()", "0")
expect("=(TODAY() + 7) - TODAY()", "7")

// MARK: - Errors

expectError("1 / 0", .divisionByZero)
expectError("=MOD(1, 0)", .divisionByZero)
expectError("0 ^ -1", .divisionByZero)
expectError("=SQRT(-1)", .number)
expectError("(-8) ^ 0.5", .number)
expectError("10 ^ 400", .number)
expectError("1e308 * 10", .number)
expectError("2 + * 3", .syntax)
expectError("2 3", .syntax)
expectError("(1 + 2", .incomplete)
expectError("=SUM(1, 2", .incomplete)
expectError("=", .incomplete)
expectError("1 +", .incomplete)
expectError("\"abc", .incomplete)
expectError("1 + 2)", .syntax)
expectError("=SUMM(1, 2)", .unknownName)
expectError("=ROUND()", .argumentCount)
expectError("=ROUND(1, 2, 3)", .argumentCount)
expectError("=PI(1)", .argumentCount)
expectError("=\"abc\" * 2", .value)
expectError("=SUM(1, , 2)", .syntax)
expectError("x + 1", .unknownName)
expectError("1 $ 2", .syntax)
expectError(String(repeating: "(", count: 200) + "1" + String(repeating: ")", count: 200), .syntax)
expectError(String(repeating: "-", count: 500) + "1", .syntax)
check(engine.calculate("=SUMM(1)").error?.message.contains("Did you mean SUM?") == true, "suggests SUM for SUMM")
check(engine.calculate("=SUMM(1)").error?.range == 1..<5, "error points at the name")
check(engine.calculate("   ") == .empty, "blank input is empty")

// MARK: - Canonical text

expectCanonical("=sum(100,200,300)", "SUM(100, 200, 300)")
expectCanonical("(1500+2500)/2", "(1500 + 2500) / 2")
expectCanonical("1+(2*3)", "1 + 2 * 3")
expectCanonical("(1+2)*3", "(1 + 2) * 3")
expectCanonical("10-(4-3)", "10 - (4 - 3)")
expectCanonical("(2^3)^2", "(2^3)^2")
expectCanonical("2^3^2", "2^3^2")
expectCanonical("-(2+3)", "-(2 + 3)")
expectCanonical("1500-15%", "1500 - 15%")
expectCanonical("=IF(1>2,\"a\",\"b\")", "IF(1 > 2, \"a\", \"b\")")
for source in ["(1500+2500)/2", "10-(4-3)", "(2^3)^2", "-(2+3)*4", "=ROUND((1500 + 2500) * 0.15, 2)", "1500 - 15%"] {
    // Printing must never change the meaning.
    guard case .value(let original, let printed) = engine.calculate(source) else { continue }
    check(engine.calculate(printed).value == original, "canonical text of \(source) re-evaluates the same")
}

// MARK: - Formatting

check(FormulaFormatter.display(1234567.891) == "1,234,567.891", "grouping")
check(FormulaFormatter.plain(1234567.891) == "1234567.891", "plain")
check(FormulaFormatter.display(-0.0) == "0", "negative zero")
check(FormulaFormatter.display(1e-12) == "1E-12", "tiny numbers in scientific")
check(FormulaFormatter.display(-2.5e20) == "-2.5E+20", "large negative in scientific")

// MARK: - Registry extensibility

var registry = FormulaFunctionRegistry.standard
registry.register(FormulaFunction("DOUBLE", category: .math, parameters: ["number"], summary: "Twice the number.", example: "DOUBLE(2)") { args in
    .number(try args.number(0) * 2)
})
let custom = FormulaEngine(functions: registry)
check(custom.calculate("=DOUBLE(SUM(1, 2))").value == .number(6), "custom functions work without parser changes")
check(engine.calculate("=DOUBLE(2)").error?.kind == .unknownName, "registering on a copy leaves the standard set alone")

// MARK: - Assistant

check(FormulaAssistant.completion(in: "=RO", caret: 3)?.names == ["ROUND", "ROUNDDOWN", "ROUNDUP"], "completes RO")
check(FormulaAssistant.completion(in: "=sum", caret: 4)?.names.first == "SUM", "exact match first")
check(FormulaAssistant.completion(in: "=SUM(1)", caret: 4) == nil, "no completion for an existing call")
check(FormulaAssistant.completion(in: "=XYZ", caret: 4) == nil, "no completion without matches")
check(FormulaAssistant.signature(in: "=ROUND(1.5, ", caret: 12) == FormulaSignatureHint(functionName: "ROUND", argumentIndex: 1), "second ROUND argument")
check(FormulaAssistant.signature(in: "=IF(1 > 2, SUM(1, 2), ", caret: 22) == FormulaSignatureHint(functionName: "IF", argumentIndex: 2), "back in IF after SUM closes")
check(FormulaAssistant.signature(in: "=SUM((1 + 2", caret: 11)?.functionName == "SUM", "bare brackets inside a call")
check(FormulaAssistant.signature(in: "1 + 2", caret: 5) == nil, "no signature outside calls")

// MARK: - Keypad calculator

func type(_ keys: [SimpleCalculator.Key], into calculator: inout SimpleCalculator) -> SimpleCalculator.Evaluation? {
    var last: SimpleCalculator.Evaluation?
    for key in keys { last = calculator.press(key) ?? last }
    return last
}

func keys(_ text: String) -> [SimpleCalculator.Key] {
    text.compactMap { character -> SimpleCalculator.Key? in
        switch character {
        case "0"..."9": .digit(Int(String(character))!)
        case ".": .decimal
        case "+": .op(.add)
        case "-": .op(.subtract)
        case "*": .op(.multiply)
        case "/": .op(.divide)
        case "^": .op(.power)
        case "%": .percent
        case "(": .openParen
        case ")": .closeParen
        case "=": .equals
        case "±": .toggleSign
        case "<": .backspace
        case "C": .clear
        default: nil
        }
    }
}

func pad(_ text: String) -> SimpleCalculator {
    var calculator = SimpleCalculator()
    _ = type(keys(text), into: &calculator)
    return calculator
}

check(pad("100+200=").expression == "300", "keypad addition")
check(pad("1500-15%=").expression == "1275", "keypad percent off")
check(pad("(100+200)/3=").expression == "100", "keypad brackets")
check(pad("2+3*4=").expression == "14", "keypad precedence")
check(pad("(1+2").preview.value == .number(3), "preview closes brackets")
check(pad("1234.5*(2+").preview.value == .number(2469), "preview ignores a dangling operator")
check(pad("5+*").expression == "5*", "operator replaces operator")
check(pad("5*-").expression == "5*-", "minus after times starts a negative")
check(pad("5*-+").expression == "5+", "replacing a pending negative")
check(pad("..5").expression == "0.5", "one decimal point per number")
check(pad("007").expression == "7", "no leading zeros")
check(pad("2(3").expression == "2*(3", "implicit multiplication before (")
check(pad("(2)3").expression == "(2)*3", "implicit multiplication after )")
check(pad("5±").expression == "-5", "± negates")
check(pad("5±±").expression == "5", "± twice restores")
check(pad("3-5±").expression == "3+5", "± flips a subtraction")
check(pad("3*5±").expression == "3*-5", "± after times")
check(pad("(1+2)±").expression == "-(1+2)", "± on a group")
check(pad("12<").expression == "1", "backspace")
check(pad("1+2=4").expression == "4", "digit after = starts over")
check(pad("1+2=*2=").expression == "6", "operator after = continues")
check(pad("1+2=").evaluatedExpression == "1+2", "remembers what was evaluated")
check(pad("1/0=").error?.kind == .divisionByZero, "keypad division by zero")
check(pad("1/0=").expression == "1/0", "failed = keeps the expression")
check(pad("12+C").expression.isEmpty, "clear")
check(pad("(5+").expression == "(5+", "dangling operator kept while typing")
check(pad("(5+=").expression == "5", "= drops a dangling operator and closes brackets")
check(pad(")").expression.isEmpty, "unbalanced ) ignored")
check(pad(String(repeating: "9", count: 20)).expression.count == SimpleCalculator.maximumDigits, "digit limit")
check(SimpleCalculator.displayText("1500-15%*(2+-3)") == "1,500 − 15% × (2 + −3)", "display text")
check(SimpleCalculator.displayText("-5") == "−5", "unary minus display")
check(SimpleCalculator.canLoad("1,234.5 × 2"), "loads pasted numbers")
check(!SimpleCalculator.canLoad("=SUM(1,2)"), "won't load functions")
var loaded = SimpleCalculator()
check(loaded.load("=1+2") && loaded.press(.equals)?.value == .number(3), "load then evaluate")

// MARK: - Summary

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
