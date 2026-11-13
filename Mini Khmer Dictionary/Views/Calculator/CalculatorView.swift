//
//  CalculatorView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// The Calculator tab: the keypad or formula editor on the left, this
/// session's history on the right, key hints along the bottom — laid out like
/// the other two tabs.
struct CalculatorView: View {
    @ObservedObject var model: CalculatorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    modeBar
                    Divider()
                    switch model.mode {
                    case .simple: SimpleCalculatorView(model: model)
                    case .smart: SmartCalculatorView(model: model)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()

                CalculationHistoryView(model: model)
                    .frame(width: 206)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { copyToast }

            Divider()

            footer
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.copiedText)
    }

    private var modeBar: some View {
        HStack(spacing: 10) {
            Picker("Calculator", selection: $model.mode) {
                Text("Simple").tag(CalculatorMode.simple)
                Text("Smart").tag(CalculatorMode.smart)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("Simple: a keypad for everyday sums · Smart: type expressions and spreadsheet formulas")

            Text(model.mode == .simple ? "Keypad calculator" : "Expressions and =FORMULAS")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            switch model.mode {
            case .smart:
                if model.completion != nil {
                    KeyHint(keys: "\u{21E5}", label: "Complete")
                    KeyHint(keys: "\u{2191}\u{2193}", label: "Choose")
                } else {
                    KeyHint(keys: "\u{23CE}", label: "Save")
                    KeyHint(keys: "\u{2191}\u{2193}", label: "History")
                }
            case .simple:
                KeyHint(keys: "\u{23CE}", label: "Equals")
                KeyHint(keys: "\u{2191}\u{2193}", label: "History")
            }
            KeyHint(keys: "\u{2318}C", label: "Copy result")
            KeyHint(keys: "esc", label: "Clear")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var summary: String {
        let count = model.history.records.count
        return count == 0 ? "Calculator" : "\(count) in history"
    }

    @ViewBuilder
    private var copyToast: some View {
        if let copied = model.copiedText {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Copied")
                    .foregroundStyle(.secondary)
                Text(copied)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08)) }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityHidden(true)
        }
    }
}
