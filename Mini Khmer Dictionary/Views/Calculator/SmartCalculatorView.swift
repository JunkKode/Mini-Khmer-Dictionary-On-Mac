//
//  SmartCalculatorView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// The formula editor on top, a signature hint under it, and the evaluated
/// expression and result below. Completions float over the result panel so
/// nothing jumps while typing.
struct SmartCalculatorView: View {
    @ObservedObject var model: CalculatorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let examples = [
        "=SUM(100, 200, 300)",
        "=ROUND(125.678 * 1.15, 2)",
        "=IF(100 > 50, \"Pass\", \"Fail\")",
        "=DISCOUNT(2000, 15%)",
        "=PERCENTAGE(300, 2000)",
        "1500 - 15%",
    ]

    var body: some View {
        VStack(spacing: 0) {
            FormulaEditor(
                text: model.formula,
                caretRequest: model.caretRequest,
                focusRequest: model.focusRequest,
                errorRange: highlightedErrorRange,
                functions: model.functions,
                onChange: { model.editorDidChange(text: $0, selection: $1) },
                onCommand: { model.handle($0) }
            )
            .overlay(alignment: .topLeading) { placeholder }
            .frame(height: 86)

            hintBar

            Divider()

            resultPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .topLeading) { completionList }

            Divider()

            functionBar
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.completion)
    }

    /// Only real mistakes are underlined; an unfinished formula isn't one.
    private var highlightedErrorRange: Range<Int>? {
        guard let error = model.presentedCalculation.error, error.kind != .incomplete else { return nil }
        return error.range
    }

    @ViewBuilder
    private var placeholder: some View {
        if model.formula.isEmpty {
            Text("100 + 200 * 3   or   =SUM(1, 2, 3)")
                .font(Font(FormulaEditor.font))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Hint bar

    private var hintBar: some View {
        HStack(spacing: 8) {
            if let hint = model.signature, let function = model.functions.function(named: hint.functionName) {
                function.signatureText(activeArgument: hint.argumentIndex)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(function.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "lightbulb")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Start with = for spreadsheet formulas · ⇥ completes function names")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color.primary.opacity(0.035))
    }

    // MARK: - Result

    @ViewBuilder
    private var resultPanel: some View {
        switch model.presentedCalculation {
        case .empty:
            examples
        case .value(let value, let expression):
            result(value: value, expression: expression, isStale: false)
        case .failure(let error) where error.kind == .incomplete:
            if let last = model.lastValue {
                result(value: last.value, expression: last.expression, isStale: true, note: error.message)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Result")
                    Text(error.message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
        case .failure(let error):
            failure(error)
        }
    }

    private func result(value: FormulaValue, expression: String, isStale: Bool, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    sectionLabel("Expression")
                    if !isStale {
                        Button {
                            model.copyExpression()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Copy the expression as the engine understood it")
                        .accessibilityLabel("Copy expression")
                    }
                }
                Text(expression)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    sectionLabel("Result")
                    if value.typeName != "number" {
                        Text(value.typeName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(FormulaFormatter.display(value))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isStale ? .tertiary : .primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.4)
                        .textSelection(.enabled)
                        .contentTransition(.numericText())

                    if !isStale {
                        Button {
                            model.copyResult()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Copy the result (⌘C)")
                        .accessibilityLabel("Copy result")
                    }
                }
            }

            if !isStale, let words = KhmerWordsLine.words(for: value) {
                KhmerWordsLine(words: words, onCopy: model.copy)
            }

            if let note {
                Label(note, systemImage: "ellipsis.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func failure(_ error: FormulaError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Result")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(error.code)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.red)
                Text(error.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(16)
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Try")
            ForEach(Self.examples, id: \.self) { example in
                ExampleRow(text: example) {
                    model.setFormula(example)
                    model.requestFocus()
                }
            }
            Text("Results update as you type. Return saves to history; ↑ brings it back.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(16)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Completions

    @ViewBuilder
    private var completionList: some View {
        if let completion = model.completion {
            FormulaCompletionList(
                completion: completion,
                selectedIndex: model.completionIndex,
                functions: model.functions,
                onChoose: { model.acceptCompletion($0) }
            )
            .padding(.leading, 10)
            .padding(.top, 4)
            .transition(.opacity)
        }
    }

    // MARK: - Functions

    private var functionBar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(FormulaFunction.Category.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(model.functions.all.filter { $0.category == category }, id: \.name) { function in
                            Button("\(function.signature) — \(function.summary)") {
                                model.insertFunction(function.name)
                            }
                        }
                    }
                }
            } label: {
                Label("Functions", systemImage: "function")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Insert a function")

            Divider().frame(height: 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(["SUM", "ROUND", "IF", "DISCOUNT", "PERCENTOF", "PERCENTAGE", "AVERAGE", "MAX", "MIN"], id: \.self) { name in
                        Button(name) { model.insertFunction(name) }
                            .buttonStyle(FunctionChipStyle())
                            .help(model.functions.function(named: name)?.summary ?? name)
                    }
                }
                .padding(.trailing, 16)
            }
            // Fade the last chip out so a cut-off one reads as "scroll for more".
            .mask {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24)
                }
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Rows

private struct ExampleRow: View {
    let text: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                Spacer(minLength: 0)
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.09 : 0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Use this example")
    }
}

private struct FunctionChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.purple.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
    }
}

/// The result in Khmer words, under the number, with its own copy button.
struct KhmerWordsLine: View {
    let words: String
    let onCopy: (String) -> Void

    /// Words for a numeric result that is worth saying: not a date, a
    /// percentage or a huge number.
    static func words(for value: FormulaValue) -> String? {
        guard case .number(let number) = value, abs(number) < 1e12 else { return nil }
        return KhmerNumbers.words(for: number, fractionDigits: 4)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(words)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button {
                onCopy(words)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Copy in Khmer words")
            .accessibilityLabel("Copy in Khmer words")
        }
    }
}
