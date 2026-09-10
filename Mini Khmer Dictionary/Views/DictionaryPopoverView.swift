//
//  DictionaryPopoverView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// The whole popover: search field, results, and the status bar underneath.
struct DictionaryPopoverView: View {
    @Bindable var model: DictionaryModel

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
        reduceMotion ? nil : .snappy(duration: 0.22)
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                query: $model.query,
                isFocused: $searchFieldIsFocused,
                isSearching: model.isSearching,
                onSubmit: { model.copySelection(includeDefinition: false) }
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
        .background(.background)
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
        .onChange(of: model.focusRequest, initial: true) {
            searchFieldIsFocused = true
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            if model.query.isEmpty {
                dismissPopover()
            } else {
                model.clearQuery()
                searchFieldIsFocused = true
            }
            return .handled
        }
        .onKeyPress(keys: [.return]) { press in
            // Plain ⏎ is handled by the search field's onSubmit.
            guard press.modifiers.contains(.command) else { return .ignored }
            model.copySelection(includeDefinition: true)
            return .handled
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if let failure = model.failureMessage {
            ContentUnavailableView {
                Label("Dictionary unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            }
        } else if model.entries.isEmpty {
            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Searching")
            } else if model.query.isEmpty {
                ContentUnavailableView(
                    "No words loaded",
                    systemImage: "character.book.closed",
                    description: Text("The dictionary database appears to be empty.")
                )
            } else {
                ContentUnavailableView.search(text: model.query)
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
            .onChange(of: model.selection) { _, newValue in
                guard let newValue else { return }
                withAnimation(animation) {
                    proxy.scrollTo(newValue, anchor: .center)
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
