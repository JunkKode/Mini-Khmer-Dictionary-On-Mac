//
//  AppDelegate.swift
//  Mini Khmer Dictionary
//

import AppKit
import Carbon
import CoreSpotlight
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = DictionaryModel()
    private lazy var checker = SpellCheckModel(openStore: { [model] in model.openStore() })
    private let calculator = CalculatorModel()
    private let calendar = CalendarModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    private lazy var quickLookup = QuickLookupPanelController(dictionary: model) { [weak self] query in
        guard let self else { return }
        self.model.lookUp(query)
        self.showPopover()
    }
    private var isReadingSelection = false
    private lazy var clipboardPanel = ClipboardPanelController(history: .shared) { [weak self] in
        self?.settingsWindow.show()
    }
    private let settingsWindow = SettingsWindowController()
    private lazy var quickCheck = QuickCheckPanelController(openStore: { [model] in model.openStore() }) { [weak self] text in
        guard let self else { return }
        self.model.mode = .check
        self.checker.load(text)
        self.showPopover()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        AppTheme.current.apply()
        configureStatusItem()
        
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        
        // Look up the selection (⌥Space) and clipboard history (⇧⌘V), or
        // whatever keys the user chose instead.
        HotkeySettings.shared.activate(.lookUp) { [weak self] in self?.hotKeyPressed() }
        HotkeySettings.shared.activate(.checkSelection) { [weak self] in self?.checkSelectionPressed() }
        HotkeySettings.shared.activate(.clipboard) { [weak self] in self?.clipboardHotKeyPressed(keptOpen: false) }
        HotkeySettings.shared.activate(.clipboardKept) { [weak self] in self?.clipboardHotKeyPressed(keptOpen: true) }
        ClipboardHistory.shared.start()
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.model.recover() }
            }
        }
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
    
    private func applyTheme() {
        let appearance = AppTheme.current.appearance
        popover.appearance = appearance
        popover.contentViewController?.view.window?.appearance = appearance
    }
    
    private func configurePopover() {
        NotificationCenter.default.addObserver(forName: AppTheme.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView(dictionary: model, checker: checker, calculator: calculator, calendar: calendar)
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
                let menuIcon = prepareMenuBarIcon(from: rawImage)
                button.image = menuIcon
            } else {
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
        
        resized.isTemplate = false
        return resized
    }
    
    private func makeFallbackTemplateIcon() -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw book silhouette
            let bookRect = NSRect(x: 1, y: 2, width: 20, height: 14)
            let path = NSBezierPath(roundedRect: bookRect, xRadius: 3, yRadius: 3)
            NSColor.black.setFill()
            path.fill()
            
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
    
    /// ⌥Space: looks up the text selected in the frontmost app on a card
    /// beside the pointer. With nothing selected — or without the permission
    /// to read the selection — it opens the popover as before. Pressed again,
    /// it closes whichever is showing.
    /// ⇧⌘V: the clipboard history, beside the pointer. Pressed again, it
    /// closes.
    /// ⇧⌘X opens it kept open, for pasting several items. The same shortcut
    /// again closes it; the other one switches the popup to its mode.
    private func clipboardHotKeyPressed(keptOpen: Bool) {
        quickCheck.close()
        if clipboardPanel.isShown, ClipboardHistory.shared.keepsPopupOpen == keptOpen {
            clipboardPanel.close()
            return
        }
        quickLookup.close()
        clipboardPanel.show(keptOpen: keptOpen)
    }
    
    /// ⌥⇧Space: checks the spelling of the text selected in the frontmost
    /// app on a card beside the pointer, with fixes that replace the
    /// selection. With nothing selected it opens Check Spelling.
    private func checkSelectionPressed() {
        if quickCheck.isShown {
            quickCheck.close()
            return
        }
        if popover.isShown {
            hidePopover()
            return
        }
        quickLookup.close()
        if !clipboardPanel.isKeptOpen { clipboardPanel.close() }
        guard !isReadingSelection else { return }
        isReadingSelection = true
        Task {
            let result = await SelectionReader.selectedText()
            isReadingSelection = false
            switch result {
                case .text(let text):
                    quickCheck.show(text: text)
                case .needsPermission:
                    SelectionReader.requestPermission()
                    model.mode = .check
                    showPopover()
                case .noSelection:
                    model.mode = .check
                    showPopover()
            }
        }
    }
    
    private func hotKeyPressed() {
        quickCheck.close()
        if !clipboardPanel.isKeptOpen { clipboardPanel.close() }
        if quickLookup.isShown {
            quickLookup.close()
            return
        }
        if popover.isShown {
            hidePopover()
            return
        }
        guard !isReadingSelection else { return }
        isReadingSelection = true
        Task {
            let result = await SelectionReader.selectedText()
            isReadingSelection = false
            switch result {
                case .text(let text) where QuickLookupWord.isLookupable(text):
                    quickLookup.show(text: text)
                case .needsPermission:
                    SelectionReader.requestPermission()
                    showPopover()
                case .text, .noSelection:
                    showPopover()
            }
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
        quickLookup.close()
        quickCheck.close()
        
        NSApp.activate(ignoringOtherApps: true)
        applyTheme()  // the menu bar's own appearance mustn't win
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The hosting window has to be key before SwiftUI will accept focus.
        popover.contentViewController?.view.window?.makeKey()
        // Opening to an empty list (a read failed while away): try again.
        if model.needsRecovery {
            Task { await model.recover() }
        }
        switch model.mode {
            case .lookUp: model.requestSearchFocus()
            case .check: checker.requestFocus()
            case .calculate: calculator.requestFocus()
            case .calendar, .currency, .number, .units, .loan, .date: break
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
                // Keys typed in a window opened from the popover — the
                // currency picker — belong to that window, Escape included.
                if let window = event.window, window !== self.popover.contentViewController?.view.window {
                    return false
                }
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
                model.mode = .check
                checker.requestFocus()
                return true
            case 19 where command:  // ⌘2
                model.mode = .lookUp
                model.requestSearchFocus()
                return true
            case 20 where command:  // ⌘3
                model.mode = .calculate
                calculator.requestFocus()
                return true
            case 21 where command: model.mode = .calendar; return true  // ⌘4
            case 23 where command: model.mode = .currency; return true  // ⌘5
            case 22 where command: model.mode = .number; return true    // ⌘6
            case 26 where command: model.mode = .units; return true     // ⌘7
            case 28 where command: model.mode = .loan; return true      // ⌘8
            case 25 where command: model.mode = .date; return true      // ⌘9
            case 43 where command:  // ⌘, opens Settings
                hidePopover()
                settingsWindow.show()
                return true
            default:
                break
        }
        
        // Arrows move the day in the Calendar; Escape closes.
        if model.mode == .calendar {
            if event.keyCode == 53 { hidePopover(); return true }
            return calendar.handleKeyDown(event)
        }
        
        // The tools are ordinary fields and buttons: every key is theirs,
        // except Escape, which closes the popover.
        if model.mode.tool != nil {
            guard event.keyCode == 53 else { return false }
            // Escape first ends typing in a field (a currency amount keeps
            // its value), then closes the popover.
            if let window = popover.contentViewController?.view.window, window.firstResponder is NSText {
                window.makeFirstResponder(nil)
                return true
            }
            hidePopover()
            return true
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
            // Escape hides the word suggestions first, then the popover.
            if !checker.dismissCompletion() { hidePopover() }
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
        if !SelectionReader.hasPermission {
            menu.addItem(
                withTitle: "Allow \(HotkeySettings.shared.display(for: .lookUp) ?? "the Shortcut") to Look Up Selected Text…",
                action: #selector(allowSelectionLookUp),
                keyEquivalent: ""
            ).target = self
        }
        menu.addItem(.separator())
        
        let history = ClipboardHistory.shared
        let historyItem = NSMenuItem(title: HotkeySettings.shared.display(for: .clipboard).map { "Clipboard History (\($0))" } ?? "Clipboard History", action: #selector(toggleClipboardHistory), keyEquivalent: "")
        historyItem.target = self
        historyItem.state = history.isEnabled ? .on : .off
        menu.addItem(historyItem)
        let clearItem = NSMenuItem(title: "Clear Clipboard History", action: #selector(clearClipboardHistory), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = !history.items.isEmpty
        menu.addItem(clearItem)
        menu.addItem(.separator())
        
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        
        let appearance = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let themes = NSMenu()
        for theme in AppTheme.allCases {
            let item = NSMenuItem(title: theme.title, action: #selector(chooseTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.rawValue
            item.state = theme == AppTheme.current ? .on : .off
            themes.addItem(item)
        }
        appearance.submenu = themes
        menu.addItem(appearance)
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
    
    @objc private func chooseTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let theme = AppTheme(rawValue: name) else { return }
        AppTheme.choose(theme)
    }
    
    @objc private func openSettings() {
        settingsWindow.show()
    }
    
    @objc private func toggleClipboardHistory() {
        ClipboardHistory.shared.isEnabled.toggle()
    }
    
    /// Keeps pinned and favorite items, like Clear All in the popup.
    @objc private func clearClipboardHistory() {
        ClipboardHistory.shared.clear()
    }
    
    @objc private func allowSelectionLookUp() {
        SelectionReader.requestPermission()
        SelectionReader.openPermissionSettings()
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
