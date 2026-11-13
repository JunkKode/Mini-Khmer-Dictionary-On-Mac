//
//  AppDelegate.swift
//  Mini Khmer Dictionary
//

import AppKit
import Carbon
import CoreSpotlight
import ServiceManagement
import SwiftUI

/// Owns the status bar item and the popover it presents.
///
/// The popover is built once and reused, so the search text and scroll position
/// survive between openings; only keyboard focus is re-requested each time.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = DictionaryModel()
    private lazy var checker = SpellCheckModel(openStore: { [model] in model.openStore() })
    private let calculator = CalculatorModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    /// Installed only while the popover is open, so the rest of the system
    /// keeps its keys.
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()

        // Services › Check Khmer Spelling / Look Up in Khmer Dictionary, declared
        // under NSServices in Info.plist.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        GlobalHotkeyManager.shared.onHotKey = { [weak self] in
            DispatchQueue.main.async {
                self?.togglePopover()
            }
        }
        GlobalHotkeyManager.shared.register()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        if userActivity.activityType == CSSearchableItemActionType {
            if let uniqueIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                if uniqueIdentifier.hasPrefix("khmer-dict-") {
                    let parts = uniqueIdentifier.components(separatedBy: "-")
                    if parts.count >= 4 {
                        let word = parts.dropFirst(3).joined(separator: "-")
                        model.mode = .lookUp
                        showPopover()
                        model.query = word
                        model.requestSearchFocus()
                        Task {
                            await model.search()
                        }
                    }
                }
            }
            return true
        }
        return false
    }

    // MARK: - Setup

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView(dictionary: model, checker: checker, calculator: calculator)
                .environment(\.dismissPopover, DismissPopoverAction { [weak self] in
                    self?.hidePopover()
                })
        )
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        if let button = item.button {
            if let rawImage = NSImage(named: "icon") {
                // Convert opaque white background pixels and inner details into proper
                // alpha transparency so macOS template rendering doesn't draw a solid block,
                // OR render it as a properly sized icon.
                let menuIcon = prepareMenuBarIcon(from: rawImage)
                button.image = menuIcon
            } else {
                // Fallback native template icon if "icon" asset is missing
                button.image = makeFallbackTemplateIcon()
            }

            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            button.setAccessibilityLabel("Mini Khmer Dictionary")
            button.toolTip = "Mini Khmer Dictionary"
        }

        statusItem = item
    }

    /// Processes the custom `icon` asset so it displays cleanly in the macOS menu bar:
    /// 1. Resizes the image to fit the 20x20 pt macOS status bar height.
    /// 2. Sets `isTemplate = false` if the image relies on dark/light RGB contrast
    ///    (since `isTemplate = true` discards all RGB colors and turns any opaque shape solid white).
    private func prepareMenuBarIcon(from source: NSImage) -> NSImage {
        let targetSize = NSSize(width: 20, height: 20)
        let resized = NSImage(size: targetSize)

        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: source.size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        // IMPORTANT:
        // Keep `isTemplate = false` when using a multi-shade PNG (like white book + black "Mini" text).
        // If `isTemplate = true` is set, macOS ignores RGB colors and fills every non-transparent pixel
        // with solid white!
        // (Also make sure "Render As" in Xcode's Assets.xcassets for "icon" is set to "Original Image",
        // NOT "Template Image".)
        resized.isTemplate = false
        return resized
    }

    /// Optional helper: Draws a crisp monochrome template icon with transparent cutouts
    /// that automatically adapts to both Light Mode and Dark Mode menu bars.
    private func makeFallbackTemplateIcon() -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw book silhouette
            let bookRect = NSRect(x: 1, y: 2, width: 20, height: 14)
            let path = NSBezierPath(roundedRect: bookRect, xRadius: 3, yRadius: 3)
            NSColor.black.setFill()
            path.fill()

            // Punch out transparent "ក" on the left and lines on the right using .destinationOut
            NSGraphicsContext.current?.compositingOperation = .destinationOut

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
            NSString(string: "ក").draw(in: NSRect(x: 2, y: 2, width: 10, height: 13), withAttributes: attrs)

            for row in 0..<3 {
                let y = CGFloat(5 + row * 3)
                let line = NSBezierPath(roundedRect: NSRect(x: 12.5, y: y, width: 6, height: 1.4), xRadius: 0.7, yRadius: 0.7)
                line.fill()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

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
        switch model.mode {
        case .lookUp: model.requestSearchFocus()
        case .check: checker.requestFocus()
        case .calculate: calculator.requestFocus()
        }
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
        let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        switch event.keyCode {
        case 18 where command:  // ⌘1
            model.mode = .lookUp
            return true
        case 19 where command:  // ⌘2
            model.mode = .check
            return true
        case 20 where command:  // ⌘3
            model.mode = .calculate
            calculator.requestFocus()
            return true
        default:
            break
        }

        // The calculator routes its own keys; Escape clears it step by step
        // before it closes the popover.
        if model.mode == .calculate {
            if event.keyCode == 53 {  // escape
                if !calculator.handleEscape() { hidePopover() }
                return true
            }
            return calculator.handleKeyDown(event)
        }

        // The spell checker's editor needs arrows and Return for itself.
        if model.mode == .check {
            guard event.keyCode == 53 else { return false }  // escape
            hidePopover()
            return true
        }

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
        menu.addItem(
            withTitle: "Check Spelling…",
            action: #selector(checkSpellingFromMenu),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Calculator…",
            action: #selector(calculatorFromMenu),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())

        if #available(macOS 13.0, *) {
            let launchAtLoginItem = NSMenuItem(
                title: "Start at Login",
                action: #selector(toggleLaunchAtLogin),
                keyEquivalent: ""
            )
            launchAtLoginItem.target = self
            launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(launchAtLoginItem)
            
            menu.addItem(.separator())
        }
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
        model.mode = .lookUp
        showPopover()
    }

    @objc private func checkSpellingFromMenu() {
        model.mode = .check
        showPopover()
    }

    @objc private func calculatorFromMenu() {
        model.mode = .calculate
        showPopover()
    }

    // MARK: - Services

    /// Services › Check Khmer Spelling: opens the checker on the selected text.
    @objc func checkKhmerSpelling(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text was selected." as NSString
            return
        }
        model.mode = .check
        checker.load(text)
        showPopover()
    }

    /// Services › Look Up in Khmer Dictionary: searches for the selected text.
    @objc func lookUpInKhmerDictionary(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            error.pointee = "No text was selected." as NSString
            return
        }
        model.lookUp(text)
        showPopover()
    }

    @available(macOS 13.0, *)
    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        stopKeyMonitor()
    }
}
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    
    var onHotKey: (() -> Void)?
    
    private init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { _, _, _ in
            GlobalHotkeyManager.shared.onHotKey?()
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
    }
    
    func register() {
        let hotKeyID = EventHotKeyID(signature: 0x4D484B44, id: 1) // "MHKD"
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(UInt32(49), UInt32(2048), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
import CoreSpotlight
import UniformTypeIdentifiers

actor SpotlightManager {
    static let shared = SpotlightManager()
    
    func indexDatabaseIfNeeded(store: DictionaryStore) async {
        do {
            try await CSSearchableIndex.default().deleteAllSearchableItems()
        } catch {
            print("Failed to clear Spotlight index: \(error)")
        }
    }
}
