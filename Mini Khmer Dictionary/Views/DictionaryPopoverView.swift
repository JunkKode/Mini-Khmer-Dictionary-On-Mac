//
//  DictionaryPopoverView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// The whole popover: search field, results, and the status bar underneath.
struct DictionaryPopoverView: View {
    @ObservedObject var model: DictionaryModel

    @Environment(\.dismissPopover) private var dismissPopover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFieldIsFocused: Bool

    /// Width of the word list; the reading pane takes whatever is left. Kept
    /// across launches because it is a per-person preference.
    @AppStorage("listWidth") private var listWidth = Self.defaultListWidth

    private static let popoverWidth: Double = 620
    private static let defaultListWidth: Double = 268
    private static let minimumDetailWidth: Double = 250
    private static var listWidthRange: ClosedRange<Double> {
        200...(popoverWidth - minimumDetailWidth)
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                query: $model.query,
                isFocused: $searchFieldIsFocused,
                isSearching: model.isSearching
            )

            Divider()

            HStack(spacing: 0) {
                results
                    .frame(width: listWidth)

                ResizeHandle(
                    width: $listWidth,
                    range: Self.listWidthRange,
                    defaultWidth: Self.defaultListWidth
                )

                DetailPane(
                    entry: model.selectedEntry,
                    senses: model.senses,
                    onCopyWord: { model.copySelection(includeDefinition: false) },
                    onCopyEntry: { model.copySelection(includeDefinition: true) }
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { copyToast }

            Divider()

            StatusBar(
                resultCount: model.entries.count,
                totalCount: model.totalCount,
                isFiltered: !model.query.isEmpty,
                hasMore: !model.reachedEnd,
                hasSelection: model.selection != nil
            )
        }
        .frame(width: Self.popoverWidth, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(animation, value: model.copyNotice)
        .animation(animation, value: model.selection)
        .task(id: model.query) {
            // Debounce: a cancelled sleep means another keystroke arrived.
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            await model.search()
        }
        .task(id: model.selection) {
            await model.loadSenses()
        }
        .task(id: model.focusRequest) {
            searchFieldIsFocused = true
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if let failure = model.failureMessage {
            EmptyStateView(
                title: "Dictionary unavailable",
                systemImage: "exclamationmark.triangle",
                message: failure
            )
        } else if model.entries.isEmpty {
            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Searching")
            } else if model.query.isEmpty {
                EmptyStateView(
                    title: "No words loaded",
                    systemImage: "character.book.closed",
                    message: "The dictionary database appears to be empty."
                )
            } else {
                EmptyStateView(
                    title: "No matches",
                    systemImage: "magnifyingglass",
                    message: "Nothing in the dictionary matches “\(model.query)”."
                )
            }
        } else {
            entryList
        }
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.entries) { entry in
                        EntryRowView(
                            entry: entry,
                            isSelected: entry.id == model.selection,
                            showsRomanization: model.isRomanizedQuery,
                            onSelect: { model.select(entry) },
                            onCopyWord: { model.copy(entry) }
                        )
                        .id(entry.id)
                        .task { await model.loadMore(after: entry) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.automatic)
            .task(id: model.selection) {
                guard let selection = model.selection else { return }
                withAnimation(animation) {
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }

    // MARK: - Copy confirmation

    @ViewBuilder
    private var copyToast: some View {
        if let notice = model.copyNotice {
            CopyToastView(notice: notice)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

#Preview {
    DictionaryPopoverView(model: DictionaryModel())
}
