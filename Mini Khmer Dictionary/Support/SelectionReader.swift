//
//  SelectionReader.swift
//  Mini Khmer Dictionary
//

import AppKit
import ApplicationServices

/// Reads the text selected in the frontmost app, for the look-up hotkey.
///
/// The app is sandboxed, so it can't read another app's selection through
/// the Accessibility API. Instead it presses ⌘C on the user's behalf, reads
/// the pasteboard, and puts back what was there. Posting a key press needs
/// the Accessibility permission (System Settings › Privacy & Security ›
/// Accessibility), which macOS asks for the first time.
@MainActor
enum SelectionReader {
    enum Result: Equatable {
        case text(String)
        /// Nothing was selected, or the app had nothing to copy.
        case noSelection
        /// The Accessibility permission hasn't been given.
        case needsPermission
    }

    static var hasPermission: Bool {
        CGPreflightPostEventAccess()
    }

    /// Shows macOS's own prompt for the permission, once per launch at most:
    /// it does nothing more after the first refusal anyway.
    static func requestPermission() {
        guard !hasRequested else { return }
        hasRequested = true
        CGRequestPostEventAccess()
    }

    private static var hasRequested = false

    /// Opens Privacy & Security › Accessibility in System Settings.
    static func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func selectedText() async -> Result {
        guard hasPermission else { return .needsPermission }

        // The hotkey fires while ⌥ is still down; an app may read ⌥⌘C as a
        // different command, so give the user a moment to let go.
        await waitForModifierRelease()

        // This copy is the app's, not the user's: keep it out of the history.
        ClipboardHistory.shared.pause()
        defer { ClipboardHistory.shared.resume() }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let before = pasteboard.changeCount

        pressCopy()

        // Most apps answer within a few milliseconds; one that hasn't after
        // a third of a second had nothing selected.
        var copied: String?
        for _ in 0..<18 {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != before {
                copied = pasteboard.string(forType: .string)
                break
            }
        }

        if pasteboard.changeCount != before {
            restore(saved, to: pasteboard)
        }

        guard let text = copied?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .noSelection
        }
        return .text(text)
    }

    /// Waits up to half a second for the user to let go of ⌘, ⌥, ⇧ and ⌃.
    static func waitForModifierRelease() async {
        for _ in 0..<25 where !NSEvent.modifierFlags.intersection([.command, .option, .shift, .control]).isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Presses ⌘V in the frontmost app. Needs the same permission.
    static func pressPaste() {
        pressCommand(CGKeyCode(9))  // kVK_ANSI_V
    }

    private static func pressCopy() {
        pressCommand(CGKeyCode(8))  // kVK_ANSI_C
    }

    private static func pressCommand(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Keeping the user's clipboard

    private typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    private static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { types[type] = data }
            }
            return types
        }
    }

    private static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
