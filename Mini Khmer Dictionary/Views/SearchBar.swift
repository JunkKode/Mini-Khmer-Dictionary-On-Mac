//
//  SearchBar.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// Spotlight-style search field pinned to the top of the popover.
struct SearchBar: View {
    @Binding var query: String
    @FocusState.Binding var isFocused: Bool
    let isSearching: Bool
    let onSubmit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                .accessibilityHidden(true)

            TextField("ស្វែងរកពាក្យ · Search a word", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel("Search the Khmer dictionary")
                .accessibilityHint("Type Khmer text, then press Return to copy the highlighted word")

            if isSearching {
                ProgressView()
                    .controlSize(.mini)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .help("Clear the search field")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: query.isEmpty)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isSearching)
    }
}
