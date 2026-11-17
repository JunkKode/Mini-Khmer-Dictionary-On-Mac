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
expect("50%", "50%")                     // a percentage stays one
expect("200 * 10%", "20")                 // …until it's used as a number
expect("=IF(5000 >= 10000, 10%, 5%)", "5%")
expect("-15%", "-15%")
expect("50% + 10%", "60%")                // not 50% increased by a tenth
expect("50% * 2", "1")
expect("=15% = 0.15", "TRUE")
expect("=CONCAT(\"Rate: \", 15%)", "Rate: 15%")
check(FormulaFormatter.plain(.percent(0.125)) == "12.5%", "percentages copy with their sign")
check(engine.calculate("12.5%").value == .percent(0.125), "copied percentages read back the same")

// MARK: - Percentage functions

expect("=PERCENTOF(15%, 2000)", "300")
expect("=PERCENTOF(15, 2000)", "300")     // plain numbers are percentage points
expect("=PERCENTOF(0.15, 2000)", "3")     // …so 0.15 means 0.15%
expect("=DISCOUNT(2000, 15%)", "1,700")
expect("=DISCOUNT(2000, 15)", "1,700")
expect("=DISCOUNT(99.99, 12.5%)", "87.49125")
expect("=DISCOUNT(2000, 0%)", "2,000")
expect("=DISCOUNT(2000, 100%)", "0")
expect("=ADDPERCENT(2000, 10%)", "2,200")
expect("=ADDPERCENT(2000, 150%)", "5,000")
expect("=ADDPERCENT(2000, -10%)", "1,800")
expect("=PERCENTAGE(300, 2000)", "15%")
expect("=PERCENTAGE(1, 3)", "33.3333333333%")
expect("=PERCENTAGE(-50, 200)", "-25%")
expect("=PERCENTCHANGE(1500, 1800)", "20%")
expect("=PERCENTCHANGE(1800, 1500)", "-16.6666666667%")
expect("=PERCENTCHANGE(-100, -50)", "50%")
expect("=ROUND(PERCENTAGE(1, 3), 2)", "33.33%")  // rounds the percent as shown
expect("=ROUNDUP(PERCENTAGE(1, 3), 0)", "34%")
expect("=ROUNDDOWN(PERCENTCHANGE(1800, 1500), 1)", "-16.6%")
expect("=ABS(PERCENTCHANGE(1800, 1500))", "16.6666666667%")
expect("=ROUND(123.456, 2)", "123.46")    // numbers are unaffected
expect("=DISCOUNT(2000, PERCENTAGE(300, 2000))", "1,700")  // functions chain
expect("=ADDPERCENT(DISCOUNT(1000, 20%), 10%)", "880")
expect("=PERCENTOF(10%, SUM(100, 200, 300))", "60")
expect("=IF(PERCENTCHANGE(100, 130) > 25%, \"Big\", \"Small\")", "Big")
expectError("=DISCOUNT(2000, 150%)", .number)
expectError("=DISCOUNT(2000, -5%)", .number)
expectError("=PERCENTAGE(300, 0)", .divisionByZero)
expectError("=PERCENTCHANGE(0, 10)", .divisionByZero)
expectError("=DISCOUNT(2000)", .argumentCount)
expectError("=PERCENTOF(\"abc\", 10)", .value)

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
for source in ["(1500+2500)/2", "10-(4-3)", "(2^3)^2", "-(2+3)*4", "=ROUND((1500 + 2500) * 0.15, 2)", "1500 - 15%", "-15%", "=DISCOUNT(2000, 15%)"] {
    // Printing must never change the meaning.
    guard case .value(let original, let printed) = engine.calculate(source) else { continue }
    check(engine.calculate(printed).value == original, "canonical text of \(source) re-evaluates the same")
}

// MARK: - Cell references (Smart mode has no cells)

expectError("A1 + 1", .reference)
expectError("=SUM(A1:A3)", .reference)
check(engine.calculate("=A1").error?.message.contains("Grid") == true, "explains references need the Grid")
expectError("=A1:", .incomplete)
expectError("=A1:5", .syntax)
expectError("=1:2", .syntax)
check((try? FormulaParser.parse("=sum(a1:b2)+c3"))?.canonicalText == "SUM(A1:B2) + C3", "prints references in capitals")
check(CellAddress("B12") == CellAddress(column: 1, row: 11), "parses B12")
check(CellAddress("aa1") == CellAddress(column: 26, row: 0), "two-letter columns")
check(CellAddress("A0") == nil && CellAddress("A") == nil && CellAddress("1A") == nil && CellAddress("ABC1") == nil, "rejects non-cells")
check(CellAddress(column: 27, row: 99).name == "AB100", "names cells")
check(FormulaAssistant.accept("ROUND", from: FormulaAssistant.completion(in: "=RO", caret: 3)!, in: "=RO") == ("=ROUND()", 7), "accepting a completion")

// MARK: - Spreadsheet

func sheet(_ cells: [String: String]) -> Spreadsheet {
    var sheet = Spreadsheet()
    for (name, input) in cells { sheet.setInput(input, at: CellAddress(name)!) }
    return sheet
}

func shown(_ sheet: Spreadsheet, _ name: String) -> String {
    switch sheet.result(at: CellAddress(name)!) {
    case .empty: return "<empty>"
    case .value(let value, _): return FormulaFormatter.display(value)
    case .failure(let error): return error.code
    }
}

func expectCell(_ sheet: Spreadsheet, _ name: String, _ expected: String, line: Int = #line) {
    let actual = shown(sheet, name)
    check(actual == expected, "\(name)  →  \(actual)   (expected \(expected))", line: line)
}

var prices = sheet([
    "A1": "Item", "B1": "Price", "C1": "Qty", "D1": "Total",
    "A2": "Pen", "B2": "1,500", "C2": "3", "D2": "=B2*C2",
    "A3": "Book", "B3": "12000", "C3": "2", "D3": "=b3 * c3",
    "C4": "Sum", "D4": "=SUM(D1:D3)",
    "C5": "Off", "D5": "=DISCOUNT(D4, 10%)",
    "C6": "Avg", "D6": "=AVERAGE(B1:B3)",
])
expectCell(prices, "A1", "Item")
expectCell(prices, "B2", "1,500")
expectCell(prices, "D2", "4,500")
expectCell(prices, "D4", "28,500")            // the "Total" heading is skipped
expectCell(prices, "D5", "25,650")
expectCell(prices, "D6", "6,750")
prices.setInput("4", at: CellAddress("C2")!)  // everything downstream updates
expectCell(prices, "D2", "6,000")
expectCell(prices, "D4", "30,000")
expectCell(prices, "D5", "27,000")
prices.setInput("", at: CellAddress("A1")!)
check(prices.input(at: CellAddress("A1")!).isEmpty && prices.result(at: CellAddress("A1")!) == .empty, "clearing a cell")
check(prices.plainText(at: CellAddress("D4")!) == "30000", "copies the plain value")

// Copying formulas: references move with the paste, as in a spreadsheet.
check(Spreadsheet.shiftingReferences(in: "=A1+B2", columns: 0, rows: 1) == "=A2+B3", "shifts references down")
check(Spreadsheet.shiftingReferences(in: "=SUM(A1:B3) * c1", columns: 2, rows: 0) == "=SUM(C1:D3) * E1", "shifts ranges across")
check(Spreadsheet.shiftingReferences(in: "=LOG10(A2)", columns: 1, rows: 0) == "=LOG10(B2)", "leaves function names alone")
check(Spreadsheet.shiftingReferences(in: "=A1", columns: -1, rows: 0) == "=#REF!", "off the edge is #REF!")
check(Spreadsheet.shiftingReferences(in: "A1", columns: 1, rows: 1) == "A1", "text isn't touched")
check(Spreadsheet.shiftingReferences(in: "=\"A1\"&B1", columns: 0, rows: 1) == "=\"A1\"&B2", "strings aren't touched")
var blockPaste = sheet(["A1": "2", "A2": "3"])
blockPaste.setBlock([["=A1*10", ""], ["=A2*10"]], at: CellAddress("B1")!)
expectCell(blockPaste, "B1", "20")
expectCell(blockPaste, "B2", "30")
check(blockPaste.input(at: CellAddress("C1")!).isEmpty, "a blank in the block clears")

let literals = sheet(["A1": "15%", "A2": "-2.5", "A3": "១២៣", "A4": "'123", "A5": "1e3", "A6": "12 apples", "A7": "=A1*200"])
expectCell(literals, "A1", "15%")
expectCell(literals, "A2", "-2.5")
expectCell(literals, "A3", "123")             // Khmer digits
expectCell(literals, "A4", "123")             // forced text…
check(literals.result(at: CellAddress("A4")!).value == .text("123"), "…stays text")
expectCell(literals, "A5", "1,000")
expectCell(literals, "A6", "12 apples")
expectCell(literals, "A7", "30")

let blanks = sheet(["A1": "=B1 + 5", "A2": "=SUM(B1:B5)", "A3": "=MAX(B1:B5)", "A4": "=COUNT(B1:B5)", "A5": "=AVERAGE(B1:B5)"])
expectCell(blanks, "A1", "5")                 // an empty cell counts as 0
expectCell(blanks, "A2", "0")
expectCell(blanks, "A3", "0")
expectCell(blanks, "A4", "0")
expectCell(blanks, "A5", "#DIV/0!")

let cycle = sheet(["A1": "=B1 + 1", "B1": "=A1 * 2", "C1": "=A1", "D1": "=D1", "E1": "5"])
expectCell(cycle, "A1", "#REF!")
expectCell(cycle, "B1", "#REF!")
expectCell(cycle, "C1", "#REF!")               // depends on the cycle
expectCell(cycle, "D1", "#REF!")
expectCell(cycle, "E1", "5")
check(cycle.result(at: CellAddress("D1")!).error?.message.contains("Circular") == true, "names the cycle")

let errors = sheet(["A1": "=1/0", "A2": "=A1 + 1", "A3": "=IF(TRUE, 1, A1)", "A4": "=G1", "A5": "=ROUND(B1:B2)", "A6": "=B1:B2", "A7": "=SUM(A1:A1)", "A8": "=SUM(1,"])
expectCell(errors, "A1", "#DIV/0!")
expectCell(errors, "A2", "#DIV/0!")            // errors carry through…
check(errors.result(at: CellAddress("A2")!).error?.message.contains("A1") == true, "…and say where from")
expectCell(errors, "A3", "1")                 // the untaken branch isn't read
expectCell(errors, "A4", "#REF!")              // outside the 6 × 30 grid
expectCell(errors, "A5", "#VALUE!")
expectCell(errors, "A6", "#VALUE!")
expectCell(errors, "A7", "#DIV/0!")
expectCell(errors, "A8", "#ERROR!")            // unfinished formulas are errors once entered

let chain = sheet(Dictionary(uniqueKeysWithValues: (1...30).map { ("A\($0)", $0 == 1 ? "1" : "=A\($0 - 1) + 1") }))
expectCell(chain, "A30", "30")

var pasted = Spreadsheet()
let written = pasted.paste("Name\tPrice\r\nTea\t2,500\nCoffee\t3000\n", at: CellAddress("B2")!)
check(written.count == 6, "pastes a block")
expectCell(pasted, "C3", "2,500")
expectCell(pasted, "B4", "Coffee")
pasted.paste("a\tb\tc\td\te\tf\tg", at: CellAddress("E1")!)
check(pasted.input(at: CellAddress("F1")!) == "b" && pasted.inputs.count == 8, "drops cells past the edge")
var restored = pasted
restored.clearAll()
check(restored.isEmpty, "clear all")
restored.restore(pasted.inputs)
check(restored == pasted && shown(restored, "C3") == "2,500", "restore recalculates")
check(prices.preview("=D4 * 2", at: CellAddress("E1")!).value == .number(60000), "previews a formula")
check(prices.input(at: CellAddress("E1")!).isEmpty, "…without entering it")
check(prices.preview("=E1", at: CellAddress("E1")!).error?.kind == .reference, "previews a self-reference as a cycle")
let partial = engine.calculate("=DI")
check(FormulaAssistant.presenting(partial, completion: FormulaAssistant.completion(in: "=DI", caret: 3)).error?.kind == .incomplete, "a name being typed isn't an error")
check(FormulaAssistant.presenting(partial, completion: nil).error?.kind == .unknownName, "…once suggestions are gone, it is")
check(FormulaFormatter.display(.number(1.0 / 3), fractionDigits: 6) == "0.333333", "cells cap decimals")
check(FormulaFormatter.display(.percent(0.254237288136), fractionDigits: 6) == "25.423729%", "…percentages too")

// MARK: - Selection

let size = (columns: 6, rows: 30)
func cell(_ name: String) -> CellAddress { CellAddress(name)! }

var selection = GridSelection(cell("B2"))
check(selection.isSingleCell && selection.current.name == "B2", "starts with one cell")
selection.extend(to: cell("D4"))
check(selection.current.name == "B2:D4" && selection.active == cell("B2"), "drag stretches from the start; the active cell stays")
selection.extend(to: cell("A1"))
check(selection.current.name == "A1:B2", "stretching up-left names the range top-left first")
check(selection.cells == [cell("A1"), cell("B1"), cell("A2"), cell("B2")], "cells row by row")
selection.select(cell("B2"))
selection.extend(columns: 1, rows: 0, within: size)
selection.extend(columns: 0, rows: 2, within: size)
check(selection.current.name == "B2:C4", "shift+arrows stretch the far corner")
selection.extend(columns: -5, rows: 0, within: size)
check(selection.current.name == "A2:B4", "…and stop at the edge")
selection.add(cell("E6"))
selection.extend(to: cell("F7"))
check(selection.ranges.count == 2 && selection.active == cell("E6"), "⌘-click adds a range and makes it active")
check(selection.contains(cell("A3")) && selection.contains(cell("F7")) && !selection.contains(cell("C3")), "contains every range")
check(selection.cells.count == 10, "counts each cell once")
check(selection.bounds.name == "A2:F7", "bounds")
check(selection.columns == [0, 1, 4, 5] && selection.rows == [1, 2, 3, 5, 6], "highlighted headers")
let edges = selection.outline(of: cell("A2"))
check(edges.top && edges.left && !edges.bottom && !edges.right, "outline edges")
check(selection.collapse() && selection.isSingleCell && selection.active == cell("E6"), "escape collapses to the active cell")
check(!selection.collapse(), "…once")
selection.move(columns: 0, rows: 40, within: size)
check(selection.active == cell("E30"), "arrows clamp")
var overlapping = GridSelection(cell("A1"))
overlapping.extend(to: cell("B2"))
overlapping.add(cell("B2"))
overlapping.extend(to: cell("C3"))
check(overlapping.cells.count == 7, "overlapping ranges count shared cells once")

// MARK: - Workbook

var book = Workbook()
check(book.sheets.map(\.name) == ["Sheet 1"] && book.canDeleteSheet == false, "starts with one sheet")
book.setInput("100", at: cell("A1"))
book.addSheet()
book.addSheet()
check(book.sheets.map(\.name) == ["Sheet 1", "Sheet 2", "Sheet 3"] && book.activeIndex == 2, "adds and shows new sheets")
check(book.active.isEmpty, "new sheets are empty")
book.activate(0)
book.groupThrough(2)
check(book.groupedIndices == [0, 1, 2] && book.activeIndex == 0, "shift-click groups a run of sheets")
book.setInput("=A1*2", at: cell("B1"))
check(book.sheets.allSatisfy { $0.cells.input(at: cell("B1")) == "=A1*2" }, "typing fills every grouped sheet")
check(book.sheets[0].cells.result(at: cell("B1")).value == .number(200) && book.sheets[1].cells.result(at: cell("B1")).value == .number(0), "…each calculating with its own cells")
book.toggleGroup(1)
check(book.groupedIndices == [0, 2], "⌘-click removes a sheet from the group")
book.toggleGroup(0)
check(book.groupedIndices.contains(0), "the active sheet stays grouped")
book.clear([cell("A1"), cell("B1")])
check(book.sheets[0].cells.isEmpty && book.sheets[2].cells.isEmpty && !book.sheets[1].cells.isEmpty, "clearing skips ungrouped sheets")
book.activate(1)
check(!book.isGrouped && book.activeIndex == 1, "a plain click ungroups")
check(!book.setInput("=A1*2", at: cell("B1")), "re-entering the same input changes nothing")
check(book.renameSheet(1, to: "  January  ") && book.sheets[1].name == "January", "renames, trimmed")
check(!book.renameSheet(2, to: "january") && !book.renameSheet(2, to: "   "), "refuses duplicate and empty names")
book.deleteSheet(0)
check(book.sheets.map(\.name) == ["January", "Sheet 3"] && book.activeIndex == 0, "deleting before the active sheet keeps it showing")
book.addSheet()
check(book.sheets.last?.name == "Sheet 4", "new names don't reuse taken ones")
for _ in 0..<20 { book.addSheet() }
check(book.sheets.count == Workbook.maximumSheets, "sheet limit")

var copyBook = Workbook()
copyBook.paste("1\t2\n3\t=A1+B1", at: cell("A1"))
check(copyBook.tabSeparatedValues(in: CellRange(cell("A1"), cell("B2"))) == "1\t2\n3\t3", "copies values as tab-separated rows")
check(copyBook.tabSeparatedValues(in: CellRange(cell("A1"), cell("B2")), selected: { $0 != cell("B1") }) == "1\t\n3\t3", "unselected cells copy blank")
var batch = Spreadsheet()
batch.setInputs([cell("A1"): "2", cell("A2"): "=A1*3", cell("A3"): "x"])
batch.setInputs([cell("A3"): ""])
check(batch.inputs.count == 2 && batch.result(at: cell("A2")).value == .number(6), "batch edits")

check(NSRange(location: 5, length: 0).clamped(toLength: 5) == NSRange(location: 5, length: 0), "a caret at the end stays there")
check(NSRange(location: 3, length: 9).clamped(toLength: 5) == NSRange(location: 3, length: 2), "ranges are trimmed")
check(NSRange(location: 9, length: 0).clamped(toLength: 5) == NSRange(location: 5, length: 0), "past the end clamps to the end")

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

// MARK: - Khmer numbers, money and the Tools models

check(KhmerNumbers.words(for: 0) == "សូន្យ", "zero")
check(KhmerNumbers.words(for: 21) == "ម្ភៃមួយ", "21")
check(KhmerNumbers.words(for: 105) == "មួយរយប្រាំ", "105")
check(KhmerNumbers.words(for: 25_000) == "ពីរម៉ឺនប្រាំពាន់", "25,000 in ម៉ឺន")
check(KhmerNumbers.words(for: 1_250_000) == "មួយលានពីរសែនប្រាំម៉ឺន", "1,250,000")
check(KhmerNumbers.words(for: 3_000_000_000) == "បីពាន់លាន", "3 billion")
check(KhmerNumbers.words(for: 12.05) == "ដប់ពីរចុចសូន្យប្រាំ", "decimals read digit by digit")
check(KhmerNumbers.words(for: -7) == "ដកប្រាំពីរ", "negative")
check(KhmerNumbers.moneyWords(for: 15_500, currency: Currency.named("KHR")!) == "មួយម៉ឺនប្រាំពាន់ប្រាំរយរៀល", "riel")
check(KhmerNumbers.moneyWords(for: 12.5, currency: Currency.named("USD")!) == "ដប់ពីរដុល្លារហាសិបសេន", "dollars and cents")
check(KhmerNumbers.digits("2026-11-15") == "២០២៦-១១-១៥", "Khmer digits")
check(KhmerNumbers.westernDigits("១២៣") == "123", "back to Western digits")
check(Currency.named("KHR")!.format(1_234_567) == "1,234,567 ៛", "riel format")
check(Currency.named("USD")!.format(-3.5) == "-$3.50", "dollar format")

let testDefaults = UserDefaults(suiteName: "formula-tests-\(UUID().uuidString)")!
let rates = ExchangeRates(defaults: testDefaults)
rates.setRate(4_000, for: "KHR")
check(rates.convert(10, from: "USD", to: "KHR") == 40_000, "USD → KHR")
check(rates.convert(8_000, from: "KHR", to: "USD") == 2, "KHR → USD")
check(ExchangeRates(defaults: testDefaults).rate("KHR") == 4_000, "rates persist")
let mixed = rates.dollarExpression(from: "$12 + 8,000៛ + ៤០០០ riel")!
check(engine.calculate(mixed).value == .number(15), "mixed currencies: \(mixed)")
check(engine.calculate(rates.dollarExpression(from: "2 usd * 3")!).value == .number(6), "plain numbers stay plain")
check(rates.dollarExpression(from: "12 + 3") == nil, "no currency, no conversion")
let fetched = try! ExchangeRates.parse(#"{"result":"success","time_last_update_unix":1700000000,"rates":{"USD":1,"KHR":4085.5}}"#.data(using: .utf8)!)
check(fetched.rates["KHR"] == 4085.5, "parses the rates service")

let grams = MeasureCategory.weight.units.first { $0.id == "chi" }!
let gram = MeasureCategory.weight.units.first { $0.id == "g" }!
check(MeasureCategory.weight.convert(2, from: grams, to: gram) == 7.5, "2 ជី is 7.5 g")
check(GoldWeight.value(grams: 3.75, pricePerDamlung: 2_000) == 200, "a ជី of gold at $2,000 a ដំឡឹង")
check(GoldWeight.breakdown(grams: 41.625).map { "\($0.count)\($0.unit)" }.joined() == "1ដំឡឹង1ជី1ហ៊ុន", "gold breakdown")
let celsius = MeasureCategory.temperature.units[0], fahrenheit = MeasureCategory.temperature.units[1]
check(MeasureCategory.temperature.convert(100, from: celsius, to: fahrenheit) == 212, "°C → °F")

let annuity = LoanSchedule(principal: 1_200, monthlyRate: 0.01, months: 12, method: .equalPayments)
check(abs(annuity.firstPayment - 106.6185) < 0.001, "equal payments: \(annuity.firstPayment)")
check(abs(annuity.rows.last!.balance) < 1e-9, "paid off")
let flat = LoanSchedule(principal: 1_200, monthlyRate: 0.015, months: 12, method: .flat)
check(abs(flat.totalInterest - 216) < 1e-9 && abs(flat.firstPayment - 118) < 1e-9, "flat rate")
let declining = LoanSchedule(principal: 1_200, monthlyRate: 0.01, months: 12, method: .equalPrincipal)
check(abs(declining.firstPayment - 112) < 1e-9 && abs(declining.lastPayment - 101) < 1e-9, "declining payments")

let calendarDate = { (y: Int, m: Int, d: Int) in DateMath.calendar.date(from: DateComponents(year: y, month: m, day: d))! }
check(DateMath.days(from: calendarDate(2026, 1, 1), to: calendarDate(2026, 12, 31)) == 364, "days between")
check(DateMath.span(from: calendarDate(1990, 5, 20), to: calendarDate(2026, 11, 15)) == (36, 5, 26), "age")
check(DateMath.workingDays(from: calendarDate(2026, 11, 16), to: calendarDate(2026, 11, 22)) == 5, "working days")
check(DateMath.khmerSolarDate(calendarDate(2026, 11, 16)) == "ថ្ងៃច័ន្ទ ទី១៦ ខែវិច្ឆិកា ឆ្នាំ២០២៦", "solar date in Khmer")
check(KhmerDateText.lunarAndSolar(calendarDate(2026, 11, 15)) == "ថ្ងៃ ៦កើត ខែកត្ដិក ឆ្នាំមមី អដ្ឋស័ក ព.ស. ២៥៧០ ត្រូវនឹង ថ្ងៃអាទិត្យ ទី១៥ ខែវិច្ឆិកា ឆ្នាំ២០២៦", "lunar and solar together: \(KhmerDateText.lunarAndSolar(calendarDate(2026, 11, 15)) ?? "nil")")

// Known holidays: Visakha Bochea, Meak Bochea, Pchum Ben and the Water Festival.
for (y, m, d, expected) in [
    (2023, 5, 4, "១៥កើត ខែពិសាខ"), (2024, 2, 24, "១៥កើត ខែមាឃ"), (2024, 5, 22, "១៥កើត ខែពិសាខ"),
    (2024, 10, 2, "១៥រោច ខែភទ្របទ"), (2024, 11, 15, "១៥កើត ខែកត្ដិក"), (2025, 5, 11, "១៥កើត ខែពិសាខ"),
    (2025, 11, 5, "១៥កើត ខែកត្ដិក"),
] {
    check(KhmerLunarCalendar.date(year: y, month: m, day: d)?.dayAndMonth == expected, "\(y)-\(m)-\(d) is \(expected)")
}
let visakha2024 = KhmerLunarCalendar.date(year: 2024, month: 5, day: 23)!
check(visakha2024.buddhistEraYear == 2568 && visakha2024.animalYear == "រោង" && visakha2024.era == "ឆស័ក", "BE year turns after Visakha Bochea")
check(KhmerLunarCalendar.date(year: 2024, month: 5, day: 22)!.buddhistEraYear == 2567, "…not on it")

check(shown("=KHMERWORDS(1250000)") == "មួយលានពីរសែនប្រាំម៉ឺន", "KHMERWORDS")
check(shown("=KHMERMONEY(12.5, \"usd\")") == "ដប់ពីរដុល្លារហាសិបសេន", "KHMERMONEY")
check(shown("=KHMERDIGITS(2026)") == "២,០២៦", "KHMERDIGITS")
check(shown("=ROUND(PMT(1%, 12, 1200), 2)") == "-106.62", "PMT")
check(shown("=DAYS(DATE(2026, 12, 31), DATE(2026, 1, 1))") == "364", "DAYS and DATE")
check(shown("=LUNAR(DATE(2024, 5, 22))").hasPrefix("១៥កើត ខែពិសាខ"), "LUNAR")
check(engine.calculate("=FX(1, \"USD\", \"XYZ\")").error != nil, "FX rejects unknown currencies")

// MARK: - Fill handle

func filled(_ inputs: [String: String], _ source: String, _ target: String, series: Bool = false) -> [String] {
    let grid = sheet(inputs)
    let parts = { (name: String) -> CellRange in
        let corners = name.split(separator: ":").map { CellAddress(String($0))! }
        return CellRange(corners[0], corners.count > 1 ? corners[1] : nil)
    }
    let source = parts(source), target = parts(target)
    let changes = GridFill.fill(source, into: target, in: grid, series: series)
    return target.cells.filter { !source.contains($0) }.map { changes[$0] ?? "" }
}
check(filled(["A1": "1", "A2": "2"], "A1:A2", "A1:A5") == ["3", "4", "5"], "continues 1, 2")
check(filled(["A1": "10", "B1": "20"], "A1:B1", "A1:E1") == ["30", "40", "50"], "continues across")
check(filled(["A1": "5"], "A1", "A1:A3") == ["5", "5"], "a single number is copied")
check(filled(["A1": "5"], "A1", "A1:A3", series: true) == ["6", "7"], "…or counts with ⌥")
check(filled(["A1": "7", "A2": "7"], "A1:A2", "A1:A4") == ["7", "7"], "identical values repeat")
check(filled(["A3": "3", "A4": "4"], "A3:A4", "A1:A4") == ["1", "2"], "fills upward backwards")
check(filled(["A1": "Item 1"], "A1", "A1:A3") == ["Item 2", "Item 3"], "numbered text counts on")
check(filled(["A1": "ថ្ងៃទី១"], "A1", "A1:A3") == ["ថ្ងៃទី២", "ថ្ងៃទី៣"], "keeps Khmer digits")
check(filled(["A1": "Room 08"], "A1", "A1:A2") == ["Room 09"], "keeps leading zeros")
check(filled(["A1": "Nov"], "A1", "A1:A3") == ["Dec", "Jan"], "months wrap round")
check(filled(["A1": "ច័ន្ទ"], "A1", "A1:A3") == ["អង្គារ", "ពុធ"], "Khmer weekdays")
check(filled(["A1": "10%", "A2": "20%"], "A1:A2", "A1:A3") == ["30%"], "percentages")
check(filled(["B1": "=A1*2"], "B1", "B1:B3") == ["=A2*2", "=A3*2"], "formulas move their references")
check(filled(["A1": "x", "A2": "y"], "A1:A2", "A1:A5") == ["x", "y", "x"], "text repeats in its pattern")
check(GridFill.target(from: CellRange(CellAddress("B2")!), to: CellAddress("C6")!) == CellRange(CellAddress("B2")!, CellAddress("B6")!), "fills along the longer drag")
check(GridFill.target(from: CellRange(CellAddress("B2")!), to: CellAddress("B2")!) == nil, "no fill inside the source")

// MARK: - Holidays

let holidays2026 = KhmerHolidays.calculated(year: 2026)
let keys = { (m: Int, d: Int) in (holidays2026[CalendarDay(year: 2026, month: m, day: d)] ?? []).map(\.key) }
check(keys(5, 1).contains("visakBochea") && keys(5, 1).contains("labourDay"), "Visak Bochea 2026 falls on Labour Day, as Google says")
check(keys(5, 5) == ["royalPloughing"], "Royal Ploughing 2026")
check(keys(10, 10) == ["pchumBen"] && keys(10, 11) == ["pchumBen"] && keys(10, 12) == ["pchumBen"], "Pchum Ben 2026")
check(keys(11, 23) == ["waterFestival"] && keys(11, 25) == ["waterFestival"], "Water Festival 2026")
let ics = """
BEGIN:VCALENDAR\r
BEGIN:VEVENT\r
DTSTART;VALUE=DATE:20261123\r
SUMMARY:Water Festival Ceremony (Day 1)\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;VALUE=DATE:20261231\r
SUMMARY:Special holiday\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;VALUE=DATE:20260502\r
SUMMARY:Visak Bochea Day\r
END:VEVENT\r
END:VCALENDAR\r
"""
let google = ICalendarReader.allDayEvents(in: ics)
check(google[CalendarDay(year: 2026, month: 11, day: 23)] == ["Water Festival Ceremony (Day 1)"], "reads iCalendar events")
check(KhmerHolidays.holidays(on: CalendarDay(year: 2026, month: 11, day: 23), google: google).first?.source == .both, "Google confirms the Water Festival")
let special = KhmerHolidays.holidays(on: CalendarDay(year: 2026, month: 12, day: 31), google: google)
check(special.first?.source == .google && special.first?.khmerName == "ថ្ងៃឈប់សម្រាកពិសេស", "Google's special day off")
let moved = KhmerHolidays.holidays(on: CalendarDay(year: 2026, month: 5, day: 1), google: google).first { $0.key == "visakBochea" }
check(moved?.note?.contains("5/2") == true, "flags a date Google disagrees on: \(moved?.note ?? "nil")")
check(KhmerHolidays.holidays(on: CalendarDay(year: 2030, month: 1, day: 7), google: google).first?.source == .calculated, "calculated outside Google's years")
check(KhmerHolidays.upcoming(from: CalendarDay(year: 2026, month: 11, day: 15), count: 2).map(\.holiday.key) == ["waterFestival", "peaceDay"], "upcoming holidays")

// MARK: - Month grid (November 2026, as in a printed Khmer calendar)

let november = KhmerMonth.days(year: 2026, month: 11)
let square = { (d: Int) in november.first { $0.day == CalendarDay(year: 2026, month: 11, day: d) }! }
check(november.count == 35 && november.first?.day == CalendarDay(year: 2026, month: 11, day: 1), "five weeks from Sunday 1st")
check(square(1).lunarLabel == "៦ រោច" && square(10).lunarLabel == "កត្ដិក", "lunar labels")
check([3, 9, 17, 24].allSatisfy { square($0).isHolyDay } && !square(10).isHolyDay, "holy days")
check(square(8).moonNote == "ថ្ងៃកោរ" && square(23).moonNote == "ថ្ងៃកោរ" && square(24).moonNote == "ពេញបូណ៌មី", "shaving day and full moon")
check(square(16).moonNote == nil, "no note on ordinary days")
check(square(9).tone == .holiday && square(23).tone == .holiday && square(26).tone == .plain, "tones")
check(KhmerMonth.lunarSpan(year: 2026, month: 11).months == "អស្សុជ - កត្ដិក ឆ្នាំមមី", "lunar span")
check(KhmerMonth.events(in: november).map { $0.day.day } == [9, 23, 24, 25], "the month's events")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
