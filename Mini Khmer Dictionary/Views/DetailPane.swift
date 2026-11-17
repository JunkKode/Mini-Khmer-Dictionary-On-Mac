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
    var followers: [String] = []
    var isSaved = false
    let onCopyWord: () -> Void
    let onCopyEntry: () -> Void
    var onToggleSave: () -> Void = {}
    var onLookUp: (String) -> Void = { _ in }
    
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
                    
                    UsageBadge(entry: entry)
                    
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
                    if !followers.isEmpty {
                        followerChips(for: entry)
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
    
    /// Words that often come next in real text; clicking one looks it up.
    private func followerChips(for entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Often followed by")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            FlowLayout(spacing: 5) {
                ForEach(followers, id: \.self) { word in
                    Button {
                        onLookUp(word)
                    } label: {
                        Text(word)
                            .font(.system(size: 12))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Look up \(word)")
                }
            }
        }
        .padding(.top, 6)
    }
    
    private func actions(showsHint: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: onToggleSave) {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "star.fill" : "star")
            }
            .tint(isSaved ? .yellow : nil)
            .help(isSaved ? "Remove from your saved words" : "Keep this word in the Saved list")
            
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
struct SenseView: View {
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

/// How common the word is in modern writing, from the corpus counts.
struct UsageBadge: View {
    let entry: DictionaryEntry
    
    var body: some View {
        let usage = entry.usage
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar < usage.level ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: 3, height: CGFloat(4 + bar * 2))
            }
            Text(usage.label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
        .frame(height: 12, alignment: .bottom)
        .help(entry.frequency > 1
              ? "Used \(entry.frequency.formatted()) times in 40 million words of modern Khmer text"
              : "Not found in modern web text; mostly literary or specialist")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage: \(usage.label)")
    }
}

/// Lays chips out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
