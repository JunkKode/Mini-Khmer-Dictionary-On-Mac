//
//  SettingsWindow.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// The Settings window. The app has no Dock icon or menu bar of its own, so
/// it's opened from the menu bar icon's menu, ⌘, in the popover, or the
/// clipboard popup.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("settings")
    /// Lets a shortcut recorder stop listening when the window goes away.
    static let willClose = Notification.Name("SettingsWindowWillClose")
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.appearance = AppTheme.current.appearance
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(hotkeys: .shared, history: .shared))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Mini Khmer Dictionary Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.identifier = Self.identifier
        window.center()
        return window
    }
    
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: Self.willClose, object: nil)
    }
}
