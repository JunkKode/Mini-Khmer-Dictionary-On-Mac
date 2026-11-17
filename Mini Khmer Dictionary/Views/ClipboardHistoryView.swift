//
//  ClipboardHistoryView.swift
//  Mini Khmer Dictionary
//

import Combine
import SwiftUI

/// What the clipboard popup is showing: the filter, the search and the
/// highlighted row. Kept apart from the history so key presses handled by
/// the panel can move the highlight.
@MainActor
final class ClipboardPanelState: ObservableObject {
    enum Filter: Hashable { case all, favorites }

    @Published var filter: Filter = .all
    @Published var search = ""
    @Published var selection: ClipboardItem.ID?
    @Published var canPaste = SelectionReader.hasPermission
    /// Bumped to put the cursor in the search field.
    @Published private(set) var focusRequest = 0

    let history: ClipboardHistory

    init(history: ClipboardHistory) {
        self.history = history
    }

    func reset() {
        filter = .all
        search = ""
        canPaste = SelectionReader.hasPermission
        selection = visibleItems.first?.id
    }

    /// Puts the cursor in the search field once the panel has the keyboard.
    func focusSearch() {
        focusRequest += 1
    }

    var visibleItems: [ClipboardItem] {
        var items = history.ordered
        if filter == .favorites { items = items.filter(\.isFavorite) }
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            items = items.filter {
                $0.text.localizedCaseInsensitiveContains(query) || ($0.sourceName?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return items
    }

    var selectedItem: ClipboardItem? {
        let items = visibleItems
        return items.first { $0.id == selection } ?? items.first
    }

    func moveSelection(by offset: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? 0
        selection = items[min(max(current + offset, 0), items.count - 1)].id
    }

    /// Keeps a highlight on screen after the list changes.
    func fixSelection() {
        let items = visibleItems
        if !items.contains(where: { $0.id == selection }) {
            selection = items.first?.id
        }
    }
}

/// The ⇧⌘V popup: what's been copied, newest first, pinned items on top.
/// Clicking an item pastes it where the user was typing.
struct ClipboardHistoryView: View {
    @ObservedObject var state: ClipboardPanelState
    @ObservedObject var history: ClipboardHistory
    let onChoose: (ClipboardItem, _ plainText: Bool) -> Void
    let onOpenSettings: () -> Void

    static let width: CGFloat = 380
    static let height: CGFloat = 480

    @FocusState private var searchFocused: Bool
    @State private var hovered: ClipboardItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if history.isEnabled {
                list
            } else {
                turnedOff
            }
            Divider()
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .onChange(of: state.focusRequest) { _ in searchFocused = true }
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .onChange(of: state.search) { _ in state.fixSelection() }
        .onChange(of: state.filter) { _ in state.fixSelection() }
        .onReceive(history.$items) { _ in DispatchQueue.main.async { state.fixSelection() } }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("Clipboard")
                        .font(.system(size: 13, weight: .semibold))
                }
                .help("Drag to move")
                Spacer()
                Picker("Show", selection: $state.filter) {
                    Text("All").tag(ClipboardPanelState.Filter.all)
                    Label("Favorites", systemImage: "star").tag(ClipboardPanelState.Filter.favorites)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                Button("Clear All") { history.clear() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5))
                    .disabled(!history.items.contains { !$0.isPinned && !$0.isFavorite })
                    .help("Remove everything except pinned and favorite items")
                Button {
                    history.keepsPopupOpen.toggle()
                } label: {
                    Image(systemName: history.keepsPopupOpen ? "pin.circle.fill" : "pin.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(history.keepsPopupOpen ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(history.keepsPopupOpen
                      ? "Kept open: paste several items, then press Esc to close (⌘D)"
                      : "Keep open after pasting, to paste several items (⌘D)")
                .accessibilityLabel("Keep open after pasting")
                .accessibilityValue(history.keepsPopupOpen ? "On" : "Off")
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings, including the shortcut for this popup")
                .accessibilityLabel("Settings")
            }
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $state.search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Dragging the top bar moves the popup, so a kept-open popup can be
        // moved off the text behind it.
        .background(WindowDragArea())
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        let items = state.visibleItems
        if items.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, number: index < 9 ? index + 1 : nil)
                                .id(item.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: state.selection) { id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func row(_ item: ClipboardItem, number: Int?) -> some View {
        let isSelected = item.id == (state.selectedItem?.id)
        let showsActions = isSelected || hovered == item.id
        return HStack(alignment: .top, spacing: 9) {
            preview(item)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 2) {
                    iconButton(item.isPinned ? "pin.fill" : "pin", active: item.isPinned,
                               help: item.isPinned ? "Unpin (⌘P)" : "Pin to the top (⌘P)") {
                        history.togglePin(item)
                    }
                    .opacity(item.isPinned || showsActions ? 1 : 0)
                    iconButton(item.isFavorite ? "star.fill" : "star", active: item.isFavorite,
                               help: item.isFavorite ? "Remove from Favorites (⌘S)" : "Add to Favorites (⌘S)") {
                        history.toggleFavorite(item)
                    }
                    .opacity(item.isFavorite || showsActions ? 1 : 0)
                    iconButton("trash", active: false, help: "Delete (⌘⌫)") {
                        history.remove(item)
                    }
                    .opacity(showsActions ? 1 : 0)
                }
                if let number {
                    Text("⌘\(number)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovered == item.id ? 0.08 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
        .onTapGesture { onChoose(item, false) }
        .contextMenu {
            Button("Paste") { onChoose(item, false) }
            if item.kind == .text, item.hasRichText {
                Button("Paste as Plain Text") { onChoose(item, true) }
            }
            Divider()
            Button(item.isPinned ? "Unpin" : "Pin") { history.togglePin(item) }
            Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") { history.toggleFavorite(item) }
            Divider()
            Button("Delete") { history.remove(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Pastes this item")
    }

    @ViewBuilder
    private func preview(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            switch item.kind {
                case .text:
                    Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 12.5))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                case .image:
                    if let image = history.thumbnail(for: item) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 220, maxHeight: 110, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else {
                        Label("Image", systemImage: "photo")
                            .font(.system(size: 12.5))
                    }
                case .files:
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(item.text.split(separator: "\n").prefix(3).enumerated()), id: \.offset) { _, name in
                            Label(String(name), systemImage: "doc")
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                        }
                        if item.files.count > 3 {
                            Text("and \(item.files.count - 3) more")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
            }
            Text(caption(for: item))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func caption(for item: ClipboardItem) -> String {
        var parts: [String] = []
        if let source = item.sourceName { parts.append(source) }
        if item.kind == .image, let width = item.imageWidth, let height = item.imageHeight {
            parts.append("\(width) × \(height)")
        }
        parts.append(Self.relativeFormatter.localizedString(for: item.date, relativeTo: Date()))
        return parts.joined(separator: " · ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private func iconButton(_ symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Empty and off

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: state.filter == .favorites ? "star" : "doc.on.clipboard")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if !state.search.trimmingCharacters(in: .whitespaces).isEmpty { return "Nothing matches “\(state.search)”." }
        if state.filter == .favorites { return "Star an item to keep it here." }
        return "Copy something and it will show up here."
    }

    private var turnedOff: some View {
        VStack(spacing: 10) {
            Text("Clipboard history is off.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Button("Turn On") { history.isEnabled = true }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if state.canPaste {
            Text(history.keepsPopupOpen
                 ? "Kept open · drag the top bar to move · esc closes"
                 : "⏎ paste · ⌥⏎ plain text · ⌘P pin · ⌘S favorite · ⌘D keep open")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        } else {
            HStack(spacing: 6) {
                Text("Items are copied; allow Accessibility to paste them for you.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("Allow…") {
                    SelectionReader.requestPermission()
                    SelectionReader.openPermissionSettings()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }
}

/// An area that drags its window: AppKit's own window drag, which works on a
/// borderless panel and even while another app is in front.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
    
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
