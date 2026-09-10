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

        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The hosting window has to be key before SwiftUI will accept focus.
        popover.contentViewController?.view.window?.makeKey()
        model.requestSearchFocus()
    }

    private func hidePopover() {
        popover.performClose(nil)
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
