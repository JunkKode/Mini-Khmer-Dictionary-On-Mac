//
//  QuickCheckCard.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// The card the check-selection shortcut shows next to the pointer: the
/// selected text with red lines under unknown words and blue lines under
/// words with a known fix, and the fixes to click.
struct QuickCheckCard: View {
    @ObservedObject var model: QuickCheckModel
    let onReplace: () -> Void
    let onOpenInChecker: () -> Void
    let onHeightChange: (CGFloat) -> Void

    static let width: CGFloat = 400
    static let maximumHeight: CGFloat = 520

    static let mistakeColor = Color(nsColor: .systemRed)
    static let fixColor = Color(nsColor: .systemBlue)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onHeightChange(proxy.size.height) }
                    .onChange(of: proxy.size.height) { onHeightChange($0) }
            }
        )
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.issues.map(\.id))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Spelling")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if model.phase == .ready {
                if model.mistakeCount > 0 {
                    countBadge(model.mistakeCount, model.mistakeCount == 1 ? "mistake" : "mistakes", Self.mistakeColor)
                }
                if model.fixCount > 0 {
                    countBadge(model.fixCount, model.fixCount == 1 ? "fix" : "fixes", Self.fixColor)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func countBadge(_ count: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count) \(label)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Text and issues

    @ViewBuilder
    private var content: some View {
        switch model.phase {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .noKhmer:
                notice("There’s no Khmer in the selected text.")
            case .failed(let message):
                notice(message)
            case .ready:
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView {
                        Text(underlinedText)
                            .font(.system(size: 15))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 150)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))

                    if model.issues.isEmpty {
                        Label(model.hasChanges ? "All fixed." : "No mistakes found.", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.green)
                    } else {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(model.issues) { issue in
                                    issueRow(issue)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The text with a line under each issue: red or blue, thicker under the
    /// one highlighted in the list.
    private var underlinedText: AttributedString {
        var result = AttributedString(model.text)
        let selected = model.selectedIssue?.id
        for issue in model.issues {
            guard let range = Range(issue.range, in: model.text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            let color = QuickCheckModel.hasKnownFix(issue) ? Self.fixColor : Self.mistakeColor
            result[lower..<upper].underlineStyle = Text.LineStyle(pattern: .solid, color: color)
            if issue.id == selected {
                result[lower..<upper].backgroundColor = color.opacity(0.16)
            }
        }
        return result
    }

    private func issueRow(_ issue: SpellingIssue) -> some View {
        let fixable = QuickCheckModel.hasKnownFix(issue)
        let color = fixable ? Self.fixColor : Self.mistakeColor
        let isSelected = issue.id == model.selectedIssue?.id
        return HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(issue.word)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(fixable, color: color.opacity(0.7))
                    Text(description(of: issue))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Ignore") { model.ignore(issue) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    if !fixable {
                        Button("Add to Dictionary") { model.learn(issue) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                    }
                }
                if !issue.suggestions.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(Array(issue.suggestions.prefix(5).enumerated()), id: \.offset) { index, suggestion in
                            Button {
                                model.apply(suggestion, to: issue)
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 13.5, weight: index == 0 ? .semibold : .regular))
                                    .foregroundStyle(index == 0 ? Color.white : Color.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(index == 0 ? color : Color.primary.opacity(0.07))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(index == 0 && isSelected ? "Use \(suggestion) (⏎)" : "Use \(suggestion)")
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? color.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selection = issue.id }
    }

    private func description(of issue: SpellingIssue) -> String {
        switch issue.kind {
            case .unknown: issue.suggestions.isEmpty ? "Not in the dictionary" : "Not in the dictionary · did you mean"
            case .soundAlike: "Misspelled"
            case .typingOrder: "Typed in a different order"
            case .variant: "Non-standard form"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Open in Check Spelling", action: onOpenInChecker)
                .buttonStyle(.borderless)
                .font(.system(size: 11.5))
                .disabled(model.phase == .noKhmer)
            Spacer()
            if model.fixCount > 1 {
                Button("Fix All") { model.fixAll() }
                    .controlSize(.small)
                    .help("Use the first fix for every blue word")
            }
            Button("Replace Selection", action: onReplace)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.hasChanges)
                .help("Put the corrected text in place of what you selected (⌘⏎)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
