//
//  SimpleCalculatorView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

struct SimpleCalculatorView: View {
    @ObservedObject var model: CalculatorModel
    
    private var calculator: SimpleCalculator { model.simple }
    
    private let morphSpring = Animation.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.1)
    private let digitSpring = Animation.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)
    
    var body: some View {
        VStack(spacing: 0) {
            display
            Divider()
            keypad
                .padding(12)
        }
    }
    
    private var display: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(expressionLine)
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(calculator.justEvaluated ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(minHeight: 22)
                .contentTransition(.interpolate)
                .offset(y: calculator.justEvaluated ? -1 : 0)
                .scaleEffect(calculator.justEvaluated ? 0.96 : 1.0, anchor: .trailing)
                .animation(morphSpring, value: expressionLine)
                .animation(morphSpring, value: calculator.justEvaluated)
            
            Text(resultLine)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(resultIsFinal ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .textSelection(.enabled)
                .contentTransition(.numericText())
                .scaleEffect(resultIsFinal ? 1.0 : 0.96, anchor: .trailing)
                .animation(digitSpring, value: resultLine)
                .animation(morphSpring, value: resultIsFinal)
            
            if let error = calculator.error {
                Text("\(error.code)  \(error.message)")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text(khmerWords ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .contentTransition(.interpolate)
                    .opacity(khmerWords == nil ? 0 : (resultIsFinal ? 1.0 : 0.75))
                    .animation(morphSpring, value: khmerWords)
                    .animation(morphSpring, value: resultIsFinal)
                    .help(khmerWords.map { "\($0) — right-click to copy" } ?? "")
                    .contextMenu {
                        if let khmerWords {
                            Button("Copy in Khmer Words") { model.copy(khmerWords) }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(morphSpring, value: calculator.error?.code)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(expressionLine), result \(resultLine)")
    }
    
    private var khmerWords: String? {
        guard resultIsFinal || calculator.preview.value != nil,
              let value = calculator.justEvaluated || !calculator.expression.isEmpty ? calculator.preview.value : nil
                else { return nil }
        return KhmerWordsLine.words(for: value)
    }
    
    private var expressionLine: String {
        if let evaluated = calculator.evaluatedExpression {
            return SimpleCalculator.displayText(evaluated) + " ="
        }
        return SimpleCalculator.displayText(calculator.expression)
    }
    
    private var resultIsFinal: Bool {
        calculator.justEvaluated || calculator.expression.isEmpty
    }
    
    private var resultLine: String {
        if calculator.justEvaluated, let value = calculator.preview.value {
            return FormulaFormatter.display(value)
        }
        if calculator.expression.isEmpty { return "0" }
        switch calculator.preview {
            case .value(let value, _): return FormulaFormatter.display(value)
            case .failure(let error) where error.kind != .incomplete: return error.code
            default: return "…"
        }
    }
    
    private var keypad: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    keypadGrid
                }
            } else {
                keypadGrid
            }
        }
    }
    
    private var keypadGrid: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            GridRow {
                key("C", .clear, role: .function, help: "Clear (esc)")
                key("⌫", .backspace, role: .function, help: "Delete (⌫)", systemImage: "delete.left")
                key("(", .openParen, role: .function)
                key(")", .closeParen, role: .function)
                key("÷", .op(.divide), role: .operator)
            }
            GridRow {
                key("7", .digit(7))
                key("8", .digit(8))
                key("9", .digit(9))
                key("%", .percent, role: .function, help: "Percent — 1500 − 15% takes 15% off")
                key("×", .op(.multiply), role: .operator)
            }
            GridRow {
                key("4", .digit(4))
                key("5", .digit(5))
                key("6", .digit(6))
                key("±", .toggleSign, role: .function, help: "Change sign (N)")
                key("−", .op(.subtract), role: .operator)
            }
            GridRow {
                key("1", .digit(1))
                key("2", .digit(2))
                key("3", .digit(3))
                key("xʸ", .op(.power), role: .function, help: "Power (^)")
                key("+", .op(.add), role: .operator)
            }
            GridRow {
                key("0", .digit(0))
                    .gridCellColumns(2)
                key(".", .decimal)
                key("=", .equals, role: .equals, help: "Equals (⏎)")
                    .gridCellColumns(2)
            }
        }
    }
    
    @ViewBuilder
    private func key(
        _ title: String,
        _ key: SimpleCalculator.Key,
        role: KeypadButtonStyle.Role = .digit,
        help: String? = nil,
        systemImage: String? = nil
    ) -> some View {
        let button = Button {
            model.press(key)
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .medium))
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
            .focusable(false)
            .help(help ?? title)
            .accessibilityLabel(accessibilityName(title, key))
        
        if #available(macOS 26.0, *) {
            let glass: Glass = switch role {
            case .operator:
                .regular.tint(Color.accentColor.opacity(0.14)).interactive()
            case .equals:
                .regular.tint(.accentColor).interactive()
            default:
                .regular.interactive()
            }

            button
                .buttonStyle(.plain)
                .glassEffect(
                    glass,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        } else {
            button.buttonStyle(
                KeypadButtonStyle(
                    role: role,
                    isFlashing: model.flashedKey == key
                )
            )
        }
    }
    
    private func accessibilityName(_ title: String, _ key: SimpleCalculator.Key) -> String {
        switch key {
            case .clear: "Clear"
            case .backspace: "Delete"
            case .toggleSign: "Change sign"
            case .percent: "Percent"
            case .op(.add): "Plus"
            case .op(.subtract): "Minus"
            case .op(.multiply): "Times"
            case .op(.divide): "Divided by"
            case .op(.power): "To the power of"
            case .equals: "Equals"
            case .decimal: "Point"
            case .openParen: "Open bracket"
            case .closeParen: "Close bracket"
            case .digit: title
        }
    }
}

struct KeypadButtonStyle: ButtonStyle {
    enum Role { case digit, function, `operator`, equals }
    
    let role: Role
    var isFlashing = false
    
    func makeBody(configuration: Configuration) -> some View {
        KeypadKey(label: configuration.label, role: role, pressed: configuration.isPressed || isFlashing)
    }
}

private struct KeypadKey<Label: View>: View {
    let label: Label
    let role: KeypadButtonStyle.Role
    let pressed: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        label
            .font(.system(size: role == .digit ? 20 : 19, weight: role == .digit ? .regular : .medium, design: .rounded))
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(role == .equals ? 0 : 0.06))
            )
            .scaleEffect(pressed ? 0.95 : (isHovering ? 1.015 : 1.0))
            .animation(.spring(response: 0.2, dampingFraction: 0.72), value: pressed)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = $0 }
    }
    
    private var foreground: AnyShapeStyle {
        switch role {
            case .digit: AnyShapeStyle(.primary)
            case .function: AnyShapeStyle(.secondary)
            case .operator: AnyShapeStyle(Color.accentColor)
            case .equals: AnyShapeStyle(.white)
        }
    }
    
    private var fill: Color {
        let boost = (pressed ? 0.08 : 0) + (isHovering ? 0.03 : 0)
        switch role {
            case .digit: return Color.primary.opacity(0.07 + boost)
            case .function: return Color.primary.opacity(0.04 + boost)
            case .operator: return Color.accentColor.opacity(0.14 + boost * 1.5)
            case .equals: return Color.accentColor.opacity(pressed ? 0.75 : (isHovering ? 0.9 : 1))
        }
    }
}
