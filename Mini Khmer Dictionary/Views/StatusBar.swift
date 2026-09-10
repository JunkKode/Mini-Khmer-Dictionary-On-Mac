//
//  StatusBar.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// The strip along the bottom: how many words are showing, the key hints, and
/// the way out of the app.
struct StatusBar: View {
    let resultCount: Int
    let totalCount: Int
    let isFiltered: Bool
    let hasMore: Bool
    let hasSelection: Bool

    @Environment(\.dismissPopover) private var dismissPopover

    var body: some View {
        HStack(spacing: 8) {
            Text(countText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .accessibilityLabel(countText)

            Spacer(minLength: 6)

            if hasSelection {
                KeyHint(keys: "\u{23CE}", label: "Copy")
                KeyHint(keys: "\u{2318}\u{23CE}", label: "Copy entry")
            } else {
                KeyHint(keys: "\u{2191}\u{2193}", label: "Navigate")
            }

            Button {
                dismissPopover()
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit Mini Khmer Dictionary")
            .accessibilityLabel("Quit Mini Khmer Dictionary")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var countText: String {
        guard totalCount > 0 else { return "Loading…" }
        guard isFiltered else { return "\(totalCount.formatted()) words" }
        // More pages are fetched as the list scrolls, so the count is a floor.
        if hasMore { return "\(resultCount)+ matches" }
        return "\(resultCount) match\(resultCount == 1 ? "" : "es")"
    }
}

/// A keycap plus its meaning, e.g. ⏎ Copy.
private struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 4)
                .frame(minWidth: 18, minHeight: 15)
                .background(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 10))
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
