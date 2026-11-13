//
//  CalculationHistoryView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// This session's calculations, newest first. Clicking one puts it back in the
/// calculator; hovering offers a copy button; right-click has the rest.
struct CalculationHistoryView: View {
    @ObservedObject var model: CalculatorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("History")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Button {
                    model.clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.history.isEmpty)
                .help("Clear history")
                .accessibilityLabel("Clear history")
            }
            .padding(.horizontal, 12)
            .frame(height: 37)  // lines up with the mode bar beside it

            Divider()

            if model.history.isEmpty {
                EmptyStateView(
                    title: "No calculations yet",
                    systemImage: "clock.arrow.circlepath",
                    message: model.mode == .simple
                        ? "Press = to keep a result here."
                        : "Press Return to keep a result here."
                )
            } else {
                list
            }
        }
        .background(Color.primary.opacity(0.035))
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.history.records) { record in
                        HistoryRow(
                            record: record,
                            isSelected: record.id == model.historySelection,
                            onCopy: { model.copyResult(of: record) }
                        )
                        .id(record.id)
                        .onTapGesture { model.reuse(record) }
                        .contextMenu {
                            Button("Use Again") { model.reuse(record) }
                            Divider()
                            Button("Copy Result") { model.copyResult(of: record) }
                            Button("Copy Expression") { model.copyExpression(of: record) }
                            Divider()
                            Button("Remove") { model.removeFromHistory(record) }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .task(id: model.historySelection) {
                guard let selection = model.historySelection else { return }
                proxy.scrollTo(selection, anchor: .center)
            }
        }
    }
}

private struct HistoryRow: View {
    let record: CalculationRecord
    let isSelected: Bool
    let onCopy: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.expression)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("= " + record.displayResult)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .help("Copy result")
            .accessibilityLabel("Copy result")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(isHovering ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(record.source == .smart ? "Use again in Smart" : "Use again")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.expression) equals \(record.displayResult)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
