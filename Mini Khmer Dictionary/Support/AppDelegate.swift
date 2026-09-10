//
//  AppDelegate.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// Owns the status bar item and the popover it presents.
///
/// The popover is built once and reused, so the search text and scroll position
/// survive between openings; only keyboard focus is re-requested each time.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = DictionaryModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    /// Installed only while the popover is open, so the rest of the system
    /// keeps its keys.
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Setup

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: DictionaryPopoverView(model: model)
                .environment(\.dismissPopover, DismissPopoverAction { [weak self] in
                    self?.hidePopover()
                })
        )
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "character.book.closed",
            accessibilityDescription: "Mini Khmer Dictionary"
        )
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("Mini Khmer Dictionary")
        item.button?.toolTip = "Mini Khmer Dictionary"
        statusItem = item
    }

    // MARK: - Presentation

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The hosting window has to be key before SwiftUI will accept focus.
        popover.contentViewController?.view.window?.makeKey()
        model.requestSearchFocus()
        startKeyMonitor()
    }

    private func hidePopover() {
        popover.performClose(nil)
    }

    // MARK: - Keyboard

    /// Arrow keys and ⏎ have to be caught before the search field sees them —
    /// a single-line text field swallows Up and Down for its own cursor
    /// movement, so `onKeyPress` on an ancestor never runs. A local monitor
    /// gets first refusal on the event instead.
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only the Bool crosses back out: NSEvent is not Sendable.
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.popover.isShown else { return false }
                return self.handleKeyDown(event)
            }
            return consumed ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Returns `true` when the key was consumed.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126:  // up arrow
            model.moveSelection(by: -1)
        case 125:  // down arrow
            model.moveSelection(by: 1)
        case 36, 76:  // return, keypad enter
            model.copySelection(includeDefinition: event.modifierFlags.contains(.command))
        case 53:  // escape clears the query, then closes
            if model.query.isEmpty {
                hidePopover()
            } else {
                model.clearQuery()
                model.requestSearchFocus()
            }
        default:
            return false
        }
        return true
    }

    private func showContextMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open Mini Khmer Dictionary",
            action: #selector(openFromMenu),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Mini Khmer Dictionary",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // restore the click-to-toggle behaviour
    }

    @objc private func openFromMenu() {
        showPopover()
    }
}

extension AppDelegate: NSPopoverDelegate {
    /// The popover also closes by clicking away, which never routes through
    /// `hidePopover()`.
    func popoverDidClose(_ notification: Notification) {
        stopKeyMonitor()
    }
}
