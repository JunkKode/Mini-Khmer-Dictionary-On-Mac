//
//  FloatingPanel.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// A borderless panel that takes the keyboard without activating the app,
/// so the app the user was working in stays in front.
private final class FloatingCardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click even while another app is in front, so a kept-open
/// panel responds without being clicked twice.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows SwiftUI content in a floating card next to the pointer, and closes
/// it on Escape, a click anywhere else, or when it loses the keyboard. Used
/// by the quick look-up card and the clipboard history.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    let width: CGFloat
    let maximumHeight: CGFloat
    /// Gets each key press first; returns `true` when it handled it.
    /// Escape closes the panel unless this handles it.
    var onKeyDown: ((NSEvent) -> Bool)?
    /// Called whenever the panel closes, however it was closed.
    var onClose: (() -> Void)?
    /// While this says so, clicks elsewhere and losing the keyboard leave
    /// the panel open; only Escape or `close()` shut it.
    var staysOpen: () -> Bool = { false }
    /// Lets the panel be dragged by its background.
    var isMovable = false

    private let accessibilityLabel: String
    private let makeContent: () -> NSView
    private var panel: FloatingCardPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    /// Where the pointer was when the panel opened; the panel hangs below it.
    private var anchor: NSPoint = .zero
    private var height: CGFloat
    private let initialHeight: CGFloat

    init<Content: View>(
        width: CGFloat,
        height: CGFloat,
        maximumHeight: CGFloat? = nil,
        accessibilityLabel: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.height = height
        self.initialHeight = height
        self.maximumHeight = maximumHeight ?? height
        self.accessibilityLabel = accessibilityLabel
        self.makeContent = { FirstMouseHostingView(rootView: content()) }
        super.init()
    }

    var isShown: Bool {
        panel?.isVisible ?? false
    }

    /// Opens the panel beside the pointer and gives it the keyboard.
    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.appearance = AppTheme.current.appearance
        anchor = NSEvent.mouseLocation
        height = initialHeight
        place(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        startMonitors()
    }

    func close() {
        guard isShown else { return }
        stopMonitors()
        panel?.orderOut(nil)
        onClose?()
    }

    /// Resizes to fit content of `newHeight`, up to `maximumHeight`.
    func fit(height newHeight: CGFloat) {
        let clamped = min(newHeight, maximumHeight)
        guard clamped > 0, abs(clamped - height) > 0.5 else { return }
        height = clamped
        if let panel { place(panel) }
    }

    // MARK: - Panel

    private func makePanel() -> FloatingCardPanel {
        let panel = FloatingCardPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Clicking a row doesn't take the keyboard; clicking a text field does.
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = isMovable
        panel.delegate = self
        panel.setAccessibilityLabel(accessibilityLabel)

        let content = makeContent()
        content.frame = NSRect(x: 0, y: 0, width: width, height: height)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        return panel
    }

    /// Below and to the right of the pointer, kept on its screen; above the
    /// pointer when there's no room below.
    private func place(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: width, height: height)
        let gap: CGFloat = 14

        var origin = NSPoint(x: anchor.x - 24, y: anchor.y - gap - size.height)
        if origin.y < visible.minY {
            origin.y = anchor.y + gap
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Dismissal and keys

    /// Gives the keyboard back to the app the user was in while keeping the
    /// panel on screen, so a paste lands there.
    func handBackKeyboard() {
        guard let panel, panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        guard !staysOpen() else { return }
        close()
    }

    private func startMonitors() {
        if clickMonitor == nil {
            // Clicks in other apps; clicks in this panel never reach it.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.staysOpen() else { return }
                    self.close()
                }
            }
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let panel = self.panel, event.window === panel else { return false }
                    if self.onKeyDown?(event) == true { return true }
                    if event.keyCode == 53 {  // escape
                        self.close()
                        return true
                    }
                    return false
                }
                return consumed ? nil : event
            }
        }
    }

    private func stopMonitors() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        clickMonitor = nil
        keyMonitor = nil
    }
}
