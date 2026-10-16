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
            rootView: PopoverRootView(dictionary: model, checker: checker)
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
        switch model.mode {
        case .lookUp: model.requestSearchFocus()
        case .check: checker.requestFocus()
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
        default:
            break
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
    /// The popover also closes by clicking away, which never routes through
    /// `hidePopover()`.
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
        // kVK_Space = 49
        // optionKey = 2048
        RegisterEventHotKey(UInt32(49), UInt32(2048), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
import CoreSpotlight
import UniformTypeIdentifiers

actor SpotlightManager {
    static let shared = SpotlightManager()
    
    func indexDatabaseIfNeeded(store: DictionaryStore) async {
        // Core Spotlight's native tokenizer has bugs with Khmer prefixes (e.g. typing សួស failing to match សួស្ដី).
        // It also doesn't allow limiting to 2-3 results. 
        // We will clear the index so it doesn't spam the user's macOS Spotlight.
        do {
            try await CSSearchableIndex.default().deleteAllSearchableItems()
        } catch {
            print("Failed to clear Spotlight index: \(error)")
        }
    }
}
