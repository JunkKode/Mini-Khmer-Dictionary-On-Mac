//
//  FormulaHelpViews.swift
//  Mini Khmer Dictionary
//

import SwiftUI

extension FormulaFunction {
    /// `ROUND(number, digits)` with the argument being typed in bold.
    func signatureText(activeArgument argument: Int) -> Text {
        let active = parameterIndex(forArgument: argument)
        var text = Text(name).foregroundColor(.purple).bold() + Text("(").foregroundColor(.secondary)
        for (index, parameter) in parameters.enumerated() {
            if index > 0 { text = text + Text(", ").foregroundColor(.secondary) }
            text = text + (index == active
                ? Text(parameter).bold().foregroundColor(.accentColor)
                : Text(parameter).foregroundColor(.secondary))
        }
        if isVariadic { text = text + Text(", …").foregroundColor(.secondary) }
        return text + Text(")").foregroundColor(.secondary)
    }
}

/// The function names that could complete what's being typed, floating under
/// a formula editor.
struct FormulaCompletionList: View {
    let completion: FormulaCompletion
    let selectedIndex: Int
    let functions: FormulaFunctionRegistry
    let onChoose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(completion.names.enumerated()), id: \.element) { index, name in
                if let function = functions.function(named: name) {
                    CompletionRow(
                        function: function,
                        isSelected: index == selectedIndex,
                        onChoose: { onChoose(name) }
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
    }
}

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
