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
                signatureText(function, argument: hint.argumentIndex)
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

    /// `ROUND(number, digits)` with the argument being typed in bold.
    private func signatureText(_ function: FormulaFunction, argument: Int) -> Text {
        let active = function.parameterIndex(forArgument: argument)
        var text = Text(function.name).foregroundColor(.purple).bold() + Text("(").foregroundColor(.secondary)
        for (index, parameter) in function.parameters.enumerated() {
            if index > 0 { text = text + Text(", ").foregroundColor(.secondary) }
            text = text + (index == active
                ? Text(parameter).bold().foregroundColor(.accentColor)
                : Text(parameter).foregroundColor(.secondary))
        }
        if function.isVariadic { text = text + Text(", …").foregroundColor(.secondary) }
        return text + Text(")").foregroundColor(.secondary)
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
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(completion.names.enumerated()), id: \.element) { index, name in
                    if let function = model.functions.function(named: name) {
                        CompletionRow(
                            function: function,
                            isSelected: index == model.completionIndex,
                            onChoose: { model.acceptCompletion(name) }
                        )
                    }
                }
            }
            .padding(4)
            .frame(width: 330)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
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
                    ForEach(["SUM", "AVERAGE", "ROUND", "IF", "MAX", "MIN", "SQRT", "MOD"], id: \.self) { name in
                        Button(name) { model.insertFunction(name) }
                            .buttonStyle(FunctionChipStyle())
                            .help(model.functions.function(named: name)?.summary ?? name)
                    }
                }
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Rows

private struct CompletionRow: View {
    let function: FormulaFunction
    let isSelected: Bool
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            VStack(alignment: .leading, spacing: 2) {
                Text(function.signature)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(function.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.accentColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

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
