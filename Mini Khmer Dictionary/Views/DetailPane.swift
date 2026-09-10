//
//  DetailPane.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// Reading area for the highlighted word. Everything here is selectable, so a
/// single sense — or one clause of one sense — can be copied by hand.
struct DetailPane: View {
    let entry: DictionaryEntry?
    let senses: [DictionarySense]
    let onCopyWord: () -> Void
    let onCopyEntry: () -> Void

    var body: some View {
        Group {
            if let entry {
                content(for: entry)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
    }

    private func content(for entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.word)
                    .font(.system(size: 19, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if !entry.pronunciation.isEmpty {
                        Text(entry.pronunciation)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !entry.roman.isEmpty {
                        Text("≈ \(entry.roman)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .help("Approximate romanization, also used for Latin search")
                    }

                    Spacer(minLength: 4)

                    if !entry.partOfSpeech.isEmpty {
                        Tag(text: entry.partOfSpeech, help: "Part of speech")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if senses.isEmpty {
                        Text(entry.gloss)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(senses.enumerated()), id: \.offset) { _, sense in
                            SenseView(sense: sense)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .id(entry.id)  // start each entry at the top

            Divider()

            ViewThatFits(in: .horizontal) {
                actions(showsHint: true)
                actions(showsHint: false)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .textSelection(.enabled)
    }

    private func actions(showsHint: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: onCopyWord) {
                Label("Copy word", systemImage: "doc.on.doc")
            }
            .help("Copy just the headword (⏎)")

            Button(action: onCopyEntry) {
                Label("Copy entry", systemImage: "text.append")
            }
            .help("Copy the word with all of its definitions (⌘⏎)")

            Spacer(minLength: 4)

            if showsHint {
                Text("Drag to select any part")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 7) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("Select a word to read its definition")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A single numbered meaning with its example sentence.
private struct SenseView: View {
    let sense: DictionarySense

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if !sense.number.isEmpty {
                    Text(sense.number)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(sense.definition)
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !sense.example.isEmpty {
                Text(sense.example)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !sense.note.isEmpty {
                Text(sense.note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
