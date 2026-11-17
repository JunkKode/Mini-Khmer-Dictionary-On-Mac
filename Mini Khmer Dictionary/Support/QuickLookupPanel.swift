//
//  QuickLookupPanel.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// Shows the quick look-up card next to the pointer for the ⌥Space hotkey.
@MainActor
final class QuickLookupPanelController {
    private let model: QuickLookupModel
    private let onOpenInDictionary: (String) -> Void
    private var floating: FloatingPanelController!

    init(dictionary: DictionaryModel, onOpenInDictionary: @escaping (String) -> Void) {
        model = QuickLookupModel(dictionary: dictionary)
        self.onOpenInDictionary = onOpenInDictionary
        floating = FloatingPanelController(
            width: QuickLookupCard.width,
            height: 120,
            maximumHeight: QuickLookupCard.maximumHeight,
            accessibilityLabel: "Khmer dictionary look-up"
        ) { [model, weak self] in
            QuickLookupCard(
                model: model,
                onOpenInDictionary: { self?.openInDictionary() },
                onClose: { self?.close() },
                onHeightChange: { self?.floating.fit(height: $0) }
            )
        }
        floating.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
    }

    var isShown: Bool {
        floating.isShown
    }

    func show(text: String) {
        floating.show()
        Task { await model.load(text) }
    }

    func close() {
        floating.close()
    }

    private func openInDictionary() {
        let query = model.queryForDictionary
        close()
        onOpenInDictionary(query)
    }

    /// ⌘C copies the word and ⇧⌘C the whole entry; the arrows step through
    /// the words of a phrase; ⌘S saves.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
            case 8 where flags == .command:  // ⌘C
                model.copy()
            case 8 where flags == [.command, .shift]:  // ⇧⌘C
                model.copy(includeDefinition: true)
            case 1 where flags == .command:  // ⌘S
                model.toggleSaved()
            case 123, 126:  // left, up
                model.moveSelection(by: -1)
            case 124, 125:  // right, down
                model.moveSelection(by: 1)
            default:
                return false
        }
        return true
    }
}
