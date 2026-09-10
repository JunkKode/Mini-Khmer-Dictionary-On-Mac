//
//  EntryRowView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// One word in the list. Clicking a row only selects it — the definition is
/// read in the pane below, and copying is always an explicit action.
struct EntryRowView: View {
    let entry: DictionaryEntry
    let isSelected: Bool
    /// Shows the Latin transcription, so a romanized search explains its matches.
    let showsRomanization: Bool
    let onSelect: () -> Void
    let onCopyWord: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.word)
                    .font(.system(size: 15, weight: .medium))

                if showsRomanization, !entry.roman.isEmpty {
                    Text(entry.roman)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else if !entry.pronunciation.isEmpty {
                    Text(entry.pronunciation)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if entry.isCompound {
                    Tag(text: "ផ្សំ", help: "Compound word")
                }
                if !entry.partOfSpeech.isEmpty {
                    Tag(text: entry.partOfSpeech, help: "Part of speech")
                }
            }

            if !entry.gloss.isEmpty {
                Text(entry.gloss)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Shows the definition below")
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: "Copy word", onCopyWord)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(fillStyle)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isSelected ? 0.45 : 0), lineWidth: 1)
            }
    }

    private var fillStyle: AnyShapeStyle {
        if isSelected {
            AnyShapeStyle(Color.accentColor.opacity(0.16))
        } else if isHovering {
            AnyShapeStyle(Color.primary.opacity(0.06))
        } else {
            AnyShapeStyle(.clear)
        }
    }
}

/// Small capsule used for the part of speech and the compound marker.
struct Tag: View {
    let text: String
    let help: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .help(help)
            .accessibilityLabel("\(help): \(text)")
    }
}
