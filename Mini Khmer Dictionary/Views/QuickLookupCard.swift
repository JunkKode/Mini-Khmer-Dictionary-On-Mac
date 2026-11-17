//
//  QuickLookupCard.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// The small card that the look-up hotkey shows next to the pointer, for
/// text selected in another app.
struct QuickLookupCard: View {
    @ObservedObject var model: QuickLookupModel
    let onOpenInDictionary: () -> Void
    let onClose: () -> Void
    /// Reports the card's natural height, so the panel can fit it.
    let onHeightChange: (CGFloat) -> Void

    static let width: CGFloat = 360
    static let maximumHeight: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.words.count > 1 {
                wordChips
                Divider()
            }
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
    }

    // MARK: - Words of a phrase

    private var wordChips: some View {
        FlowLayout(spacing: 5) {
            ForEach(model.words) { word in
                let isSelected = word.index == model.selectedIndex
                Button {
                    model.select(word)
                } label: {
                    Text(word.typed)
                        .font(.system(size: 13))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                        )
                        .foregroundStyle(word.entry == nil ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .disabled(word.entry == nil)
                .help(word.entry == nil ? "Not in the dictionary" : "Show \(word.entry?.word ?? word.typed)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityLabel("Words in the selection")
    }

    // MARK: - Entry

    @ViewBuilder
    private var content: some View {
        switch model.phase {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking up “\(model.text)”…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .failed(let message):
                notice(message)
            case .ready:
                if let word = model.selected, let entry = word.entry {
                    entryView(entry, isGuess: word.isGuess, typed: word.typed)
                } else {
                    notice("“\(model.text)” isn’t in the dictionary.")
                }
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryView(_ entry: DictionaryEntry, isGuess: Bool, typed: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                if isGuess {
                    Text("No entry for “\(typed)”. Closest spelling:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.word)
                        .font(.system(size: 20, weight: .semibold))
                        .textSelection(.enabled)
                    if !entry.pronunciation.isEmpty {
                        Text(entry.pronunciation)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if !entry.partOfSpeech.isEmpty {
                        Tag(text: entry.partOfSpeech, help: "Part of speech")
                    }
                }
                HStack(spacing: 6) {
                    if !entry.roman.isEmpty {
                        Text("≈ \(entry.roman)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    UsageBadge(entry: entry)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if model.senses.isEmpty {
                        Text(entry.gloss)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(model.senses.enumerated()), id: \.offset) { _, sense in
                            SenseView(sense: sense)
                        }
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: SensesHeight.self, value: proxy.size.height)
                    }
                )
            }
            .frame(height: sensesHeight)
            .onPreferenceChange(SensesHeight.self) { sensesHeight = min($0, 300) }
        }
    }

    @State private var sensesHeight: CGFloat = 60

    private struct SensesHeight: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    // MARK: - Actions

    private var footer: some View {
        HStack(spacing: 10) {
            let hasEntry = model.selected?.entry != nil
            Button {
                model.toggleSaved()
            } label: {
                Image(systemName: model.isSaved ? "star.fill" : "star")
                    .foregroundStyle(model.isSaved ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!hasEntry)
            .help(model.isSaved ? "Remove from Saved" : "Save")
            .accessibilityLabel(model.isSaved ? "Remove from Saved" : "Save")

            Button(model.copied ? "Copied" : "Copy") {
                model.copy()
            }
            .buttonStyle(.borderless)
            .disabled(!hasEntry)
            .help("Copy the word (⌘C) · with its definition (⇧⌘C)")

            Spacer()

            Text("esc")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            Button("Open in Dictionary", action: onOpenInDictionary)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .help("Show this in the full dictionary (⏎)")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
