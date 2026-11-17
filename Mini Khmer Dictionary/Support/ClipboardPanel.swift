//
//  ClipboardPanel.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// The ⇧⌘V clipboard history popup. Choosing an item puts it on the
/// pasteboard, closes the popup (unless it's kept open) and presses ⌘V in
/// the app the user was in.
@MainActor
final class ClipboardPanelController {
    private let history: ClipboardHistory
    private let state: ClipboardPanelState
    private var floating: FloatingPanelController!

    init(history: ClipboardHistory, onOpenSettings: @escaping () -> Void) {
        self.history = history
        state = ClipboardPanelState(history: history)
        floating = FloatingPanelController(
            width: ClipboardHistoryView.width,
            height: ClipboardHistoryView.height,
            accessibilityLabel: "Clipboard history"
        ) { [state, history, weak self] in
            ClipboardHistoryView(
                state: state,
                history: history,
                onChoose: { item, plainText in self?.choose(item, plainText: plainText) },
                onOpenSettings: {
                    self?.close()
                    onOpenSettings()
                }
            )
        }
        floating.staysOpen = { [history] in history.keepsPopupOpen }
        floating.isMovable = true
        floating.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
    }

    var isShown: Bool {
        floating.isShown
    }

    /// Opens the popup; `keptOpen` decides whether it stays after pasting.
    func show(keptOpen: Bool) {
        history.keepsPopupOpen = keptOpen
        guard !isShown else { return }
        state.reset()
        floating.show()
        state.focusSearch()
    }

    func close() {
        floating.close()
    }

    /// Whether the popup is open and set to stay open.
    var isKeptOpen: Bool {
        isShown && history.keepsPopupOpen
    }
    
    private func choose(_ item: ClipboardItem, plainText: Bool) {
        history.write(item, plainText: plainText, moveToTop: !history.keepsPopupOpen)
        if history.keepsPopupOpen {
            // Stay on screen for the next item, but let the paste land in the
            // app the user was typing in.
            floating.handBackKeyboard()
        } else {
            close()
        }
        // Without the permission the item is only copied; the footer says so.
        guard SelectionReader.hasPermission else { return }
        Task {
            await SelectionReader.waitForModifierRelease()
            // Let the app that was in front take the keyboard back first.
            try? await Task.sleep(for: .milliseconds(60))
            SelectionReader.pressPaste()
        }
    }

    /// ↑↓ move, ⏎ pastes (⌥⏎ as plain text), ⌘1–⌘9 paste by position,
    /// ⌘P pins, ⌘S stars, ⌘⌫ deletes. Everything else goes to the search
    /// field.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        switch event.keyCode {
            case 126:  // up
                state.moveSelection(by: -1)
            case 125:  // down
                state.moveSelection(by: 1)
            case 36, 76:  // return, enter
                guard let item = state.selectedItem else { return true }
                choose(item, plainText: flags == .option)
            case 35 where flags == .command:  // ⌘P
                if let item = state.selectedItem { history.togglePin(item) }
            case 2 where flags == .command:  // ⌘D keeps the popup open
                history.keepsPopupOpen.toggle()
            case 1 where flags == .command:  // ⌘S
                if let item = state.selectedItem { history.toggleFavorite(item) }
            case 51 where flags == .command:  // ⌘⌫
                if let item = state.selectedItem {
                    state.moveSelection(by: 1)
                    if state.selection == item.id { state.moveSelection(by: -1) }
                    history.remove(item)
                }
            case 53 where !state.search.isEmpty:  // escape clears the search first
                state.search = ""
            default:
                // ⌘1 … ⌘9
                if flags == .command, let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit) {
                    let items = state.visibleItems
                    if items.indices.contains(digit - 1) { choose(items[digit - 1], plainText: false) }
                    return true
                }
                return false
        }
        return true
    }
}
