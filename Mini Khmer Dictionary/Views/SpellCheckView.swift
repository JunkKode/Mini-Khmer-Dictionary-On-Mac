//
//  SpellCheckView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// The Check Spelling half of the popover: an editor on top, the issues found
/// below it, and the fixes for the highlighted one beside them.
struct SpellCheckView: View {
    @ObservedObject var model: SpellCheckModel
    /// Used to look a word up in the other half of the popover.
    let onLookUp: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            SpellCheckTextView(
                text: $model.text,
                issues: model.currentIssues,
                selection: model.selection,
                focusRequest: model.focusRequest,
                onSelectIssue: { model.selection = $0 }
            )
            .overlay(alignment: .topLeading) { placeholder }
            .frame(height: 190)

            Divider()

            HStack(spacing: 0) {
                issueList
                    .frame(width: 240)
                Divider()
                IssueDetail(
                    issue: model.selectedIssue,
                    onApply: { suggestion, issue in model.apply(suggestion, to: issue) },
                    onLookUp: onLookUp,
                    onLearn: model.learn,
                    onIgnore: model.ignore
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            Divider()

            footer
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.selection)
        .task(id: model.text) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await model.check()
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if model.text.isEmpty {
            Text("វាយ ឬបិទភ្ជាប់អត្ថបទខ្មែរ · Type or paste Khmer text to check")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Issues

    @ViewBuilder
    private var issueList: some View {
        if let failure = model.failureMessage {
            EmptyStateView(title: "Can't check spelling", systemImage: "exclamationmark.triangle", message: failure)
        } else if model.text.isEmpty {
            EmptyStateView(
                title: "Nothing to check",
                systemImage: "text.badge.checkmark",
                message: "Select Khmer text in any app and choose Services › Check Khmer Spelling, or paste it here."
            )
        } else if model.currentIssues.isEmpty {
            if model.isChecking || model.checkedText != model.text {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Checking")
            } else {
                EmptyStateView(
                    title: "No problems found",
                    systemImage: "checkmark.circle",
                    message: "Every Khmer word is in the dictionary."
                )
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.currentIssues) { issue in
                            IssueRow(issue: issue, isSelected: issue.id == model.selection)
                                .id(issue.id)
                                .onTapGesture { model.selection = issue.id }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .task(id: model.selection) {
                    guard let selection = model.selection else { return }
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityLabel(summary)

            Spacer(minLength: 6)

            Button("Paste", action: model.paste)
                .help("Replace the text with what's on the clipboard")
            Button("Clear", action: model.clear)
                .disabled(model.text.isEmpty)
            Button(model.didCopy ? "Copied" : "Copy Text", action: model.copyText)
                .disabled(model.text.isEmpty)
                .help("Copy the corrected text")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var summary: String {
        guard !model.text.isEmpty else { return "Check Spelling" }
        guard model.checkedText == model.text else { return "Checking…" }
        let count = model.issues.count
        return count == 0 ? "No problems" : "\(count) problem\(count == 1 ? "" : "s")"
    }
}

// MARK: - Rows

private extension SpellingIssue.Kind {
    var color: Color {
        switch self {
        case .unknown, .soundAlike: .red
        case .typingOrder, .variant: .orange
        }
    }

    var title: String {
        switch self {
        case .unknown: "Not in the dictionary"
        case .soundAlike: "Similar letters mixed up"
        case .typingOrder: "Typed in the wrong order"
        case .variant: "Different spelling in the dictionary"
        }
    }

    var explanation: String {
        switch self {
        case .unknown:
            "It may be a typo, or a name or new word the dictionary doesn't have. Add it if it's correct."
        case .soundAlike:
            "Letters that sound or look the same were probably swapped — like ា/ៀ, ូ/ោ, ៃ/ៅ, ្ដ/្ត, ំ/ម or ក/គ. Add it if it's correct."
        case .typingOrder:
            "The letters are right but were typed in a different order than standard Khmer encoding. It can look correct yet fail to search, sort or match."
        case .variant:
            "The Chuon Nath dictionary spells this word differently — often ្ដ where keyboards type ្ត, or ឱ for ឲ."
        }
    }
}

private struct IssueRow: View {
    let issue: SpellingIssue
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(issue.kind.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            // Khmer subscripts hang well below the baseline; leave them room.
            VStack(alignment: .leading, spacing: 5) {
                Text(issue.word)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(issue.suggestions.first.map { "→ \($0)" } ?? issue.kind.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(issue.word), \(issue.kind.title)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct IssueDetail: View {
    let issue: SpellingIssue?
    let onApply: (String, SpellingIssue) -> Void
    let onLookUp: (String) -> Void
    let onLearn: (SpellingIssue) -> Void
    let onIgnore: (SpellingIssue) -> Void

    var body: some View {
        Group {
            if let issue {
                content(for: issue)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
    }

    private func content(for issue: SpellingIssue) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.word)
                        .font(.system(size: 19, weight: .semibold))
                        .textSelection(.enabled)
                    Label(issue.kind.title, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(issue.kind.color)
                    Text(issue.kind.explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if issue.suggestions.isEmpty {
                    Text("No close matches in the dictionary.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replace with")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        ForEach(issue.suggestions, id: \.self) { suggestion in
                            SuggestionButton(
                                word: suggestion,
                                onApply: { onApply(suggestion, issue) },
                                onLookUp: { onLookUp(suggestion) }
                            )
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("Add to Dictionary") { onLearn(issue) }
                        .help("Stop flagging this word, now and in future")
                    Button("Ignore") { onIgnore(issue) }
                        .help("Stop flagging this word until the app quits")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}

private struct SuggestionButton: View {
    let word: String
    let onApply: () -> Void
    let onLookUp: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onApply) {
                Text(word)
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Replace with \(word)")
            .accessibilityLabel("Replace with \(word)")

            Button(action: onLookUp) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Look up \(word)")
            .accessibilityLabel("Look up \(word)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.09 : 0.05))
        )
        .onHover { isHovering = $0 }
    }
}
