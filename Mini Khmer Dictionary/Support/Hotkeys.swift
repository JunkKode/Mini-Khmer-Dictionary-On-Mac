//
//  Hotkeys.swift
//  Mini Khmer Dictionary
//

import AppKit
import Carbon
import Combine

/// A key with modifiers, as Carbon registers it.
nonisolated struct Hotkey: Codable, Equatable, Sendable {
    var keyCode: UInt32
    /// Carbon modifier flags: `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    var modifiers: UInt32
    /// The key as it was labelled when recorded, e.g. `V` or `Space`.
    var keyName: String

    /// ⌃⌥⇧⌘ order, as macOS menus write it.
    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName
    }

    /// Reads a key press, or explains why it can't be a hotkey.
    static func from(_ event: NSEvent) -> Result<Hotkey, HotkeyError> {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }

        let code = UInt32(event.keyCode)
        let name = keyName(for: event)
        let hotkey = Hotkey(keyCode: code, modifiers: modifiers, keyName: name)

        let isFunctionKey = functionKeys[code] != nil
        guard isFunctionKey || !flags.intersection([.command, .option, .control]).isEmpty else {
            return .failure(.needsModifier)
        }
        if flags == .command, ["C", "V", "X", "Z", "A", "Q", "W", "S", "N", "O", "P", "F", "H", "M", "Tab", "Space"].contains(name) {
            return .failure(.everyAppUses(hotkey.display))
        }
        return .success(hotkey)
    }

    private static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let namedKeys: [UInt32: String] = [
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    private static func keyName(for event: NSEvent) -> String {
        let code = UInt32(event.keyCode)
        if let name = functionKeys[code] ?? namedKeys[code] { return name }
        let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
        return characters.uppercased()
    }
}

nonisolated enum HotkeyError: Error, Equatable {
    case needsModifier
    case everyAppUses(String)
    case usedFor(String)
    case taken(String)

    var message: String {
        switch self {
            case .needsModifier: "Use at least one of ⌘, ⌥ or ⌃ (or a function key)."
            case .everyAppUses(let keys): "\(keys) is used by every app."
            case .usedFor(let action): "Already used for \(action)."
            case .taken(let keys): "\(keys) is already taken by macOS or another app."
        }
    }
}

/// The app's system-wide shortcuts.
enum HotkeyAction: String, CaseIterable, Identifiable {
    case lookUp, checkSelection, clipboard, clipboardKept

    var id: String { rawValue }

    var title: String {
        switch self {
            case .lookUp: "Look up selected text"
            case .checkSelection: "Check spelling of selected text"
            case .clipboard: "Clipboard history"
            case .clipboardKept: "Clipboard history, kept open"
        }
    }

    var defaultHotkey: Hotkey {
        switch self {
            case .lookUp: Hotkey(keyCode: 49, modifiers: UInt32(optionKey), keyName: "Space")
            case .checkSelection: Hotkey(keyCode: 49, modifiers: UInt32(optionKey | shiftKey), keyName: "Space")
            case .clipboard: Hotkey(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey), keyName: "V")
            case .clipboardKept: Hotkey(keyCode: 7, modifiers: UInt32(cmdKey | shiftKey), keyName: "X")
        }
    }

    fileprivate var storageKey: String { "hotkey.\(rawValue)" }
    fileprivate var carbonID: UInt32 {
        switch self {
            case .lookUp: 1
            case .clipboard: 2
            case .clipboardKept: 3
            case .checkSelection: 4
        }
    }
}

/// Which keys each shortcut uses, kept across launches and registered with
/// the system as they change. A shortcut can also be turned off.
@MainActor
final class HotkeySettings: ObservableObject {
    static let shared = HotkeySettings()

    @Published private(set) var hotkeys: [HotkeyAction: Hotkey] = [:]
    private var handlers: [HotkeyAction: () -> Void] = [:]
    private var isSuspended = false

    private struct Stored: Codable { var hotkey: Hotkey? }

    private init() {
        for action in HotkeyAction.allCases {
            if let data = UserDefaults.standard.data(forKey: action.storageKey),
               let stored = try? JSONDecoder().decode(Stored.self, from: data) {
                hotkeys[action] = stored.hotkey
            } else {
                hotkeys[action] = action.defaultHotkey
            }
        }
    }

    func hotkey(for action: HotkeyAction) -> Hotkey? {
        hotkeys[action]
    }

    /// What a menu should show for `action`, or `nil` when it's off.
    func display(for action: HotkeyAction) -> String? {
        hotkeys[action]?.display
    }

    /// Registers `action`'s shortcut and runs `handler` when it's pressed.
    func activate(_ action: HotkeyAction, handler: @escaping () -> Void) {
        handlers[action] = handler
        if let hotkey = hotkeys[action], !GlobalHotkeyManager.shared.register(hotkey, id: action.carbonID, action: handler) {
            print("Couldn't register \(hotkey.display) for \(action.title)")
        }
    }

    /// Changes `action` to `hotkey` (`nil` turns it off). Keeps the old one
    /// and returns why when the new one can't be used.
    @discardableResult
    func change(_ action: HotkeyAction, to hotkey: Hotkey?) -> HotkeyError? {
        if let hotkey, let other = HotkeyAction.allCases.first(where: { $0 != action && hotkeys[$0] == hotkey }) {
            return .usedFor(other.title.lowercased())
        }
        let old = hotkeys[action]
        guard hotkey != old else { return nil }

        if !isSuspended, let handler = handlers[action] {
            GlobalHotkeyManager.shared.unregister(id: action.carbonID)
            if let hotkey, !GlobalHotkeyManager.shared.register(hotkey, id: action.carbonID, action: handler) {
                if let old { GlobalHotkeyManager.shared.register(old, id: action.carbonID, action: handler) }
                return .taken(hotkey.display)
            }
        }
        hotkeys[action] = hotkey
        if let data = try? JSONEncoder().encode(Stored(hotkey: hotkey)) {
            UserDefaults.standard.set(data, forKey: action.storageKey)
        }
        return nil
    }

    /// Releases every shortcut while a new one is being typed, so pressing
    /// the current keys records them instead of triggering them.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        for action in HotkeyAction.allCases {
            GlobalHotkeyManager.shared.unregister(id: action.carbonID)
        }
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        for action in HotkeyAction.allCases {
            if let hotkey = hotkeys[action], let handler = handlers[action] {
                GlobalHotkeyManager.shared.register(hotkey, id: action.carbonID, action: handler)
            }
        }
    }

    /// Checks that `hotkey` is free by registering it briefly. Only
    /// meaningful while suspended, when the app's own shortcuts are released.
    func isAvailable(_ hotkey: Hotkey) -> Bool {
        let probe: UInt32 = 99
        guard GlobalHotkeyManager.shared.register(hotkey, id: probe, action: {}) else { return false }
        GlobalHotkeyManager.shared.unregister(id: probe)
        return true
    }
}

/// System-wide hotkeys through Carbon, the only API for them that works in
/// the sandbox.
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var actions: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]

    private init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let id = hotKeyID.id
            DispatchQueue.main.async {
                GlobalHotkeyManager.shared.actions[id]?()
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
    }

    /// Registers `hotkey` under `id`, replacing what `id` had. Returns
    /// `false` when another app (or macOS) already holds the combination.
    @discardableResult
    func register(_ hotkey: Hotkey, id: UInt32, action: @escaping () -> Void) -> Bool {
        unregister(id: id)
        let hotKeyID = EventHotKeyID(signature: 0x4D484B44, id: id) // "MHKD"
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        actions[id] = action
        references[id] = reference
        return true
    }

    func unregister(id: UInt32) {
        if let reference = references.removeValue(forKey: id) {
            UnregisterEventHotKey(reference)
        }
        actions[id] = nil
    }
}
