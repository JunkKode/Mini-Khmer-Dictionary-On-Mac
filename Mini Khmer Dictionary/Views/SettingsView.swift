//
//  SettingsView.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// Shortcuts and clipboard history options.
struct SettingsView: View {
    @ObservedObject var hotkeys: HotkeySettings
    @ObservedObject var history: ClipboardHistory

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        HotkeyRecorder(action: action, settings: hotkeys)
                    }
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Click a shortcut, then press the new keys. Esc cancels. These work in every app. The kept-open clipboard stays on screen after pasting, for pasting several items; ⌘D switches it in the popup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Clipboard History") {
                Toggle("Keep a history of what I copy", isOn: $history.isEnabled)
                LabeledContent("Saved items") {
                    HStack {
                        Text("\(history.items.count)")
                            .foregroundStyle(.secondary)
                        Button("Clear History") { history.clear() }
                            .disabled(!history.items.contains { !$0.isPinned && !$0.isFavorite })
                            .help("Removes everything except pinned and favorite items")
                    }
                }
            }

            if !SelectionReader.hasPermission {
                Section("Permission") {
                    LabeledContent("Reading selections and pasting need Accessibility access.") {
                        Button("Allow…") {
                            SelectionReader.requestPermission()
                            SelectionReader.openPermissionSettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A button that shows a shortcut and, once clicked, records the next key
/// combination typed.
struct HotkeyRecorder: View {
    let action: HotkeyAction
    @ObservedObject var settings: HotkeySettings

    @State private var isRecording = false
    @State private var error: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    isRecording ? stop() : start()
                } label: {
                    Text(label)
                        .font(.system(size: 12.5, weight: isRecording ? .regular : .medium))
                        .foregroundStyle(isRecording || settings.hotkey(for: action) == nil ? .secondary : .primary)
                        .frame(minWidth: 110)
                }
                .help(isRecording ? "Press the new shortcut, or Esc to cancel" : "Click to change")

                Menu {
                    Button("Turn Off") {
                        stop()
                        settings.change(action, to: nil)
                    }
                    .disabled(settings.hotkey(for: action) == nil)
                    Button("Reset to \(action.defaultHotkey.display)") {
                        stop()
                        error = settings.change(action, to: action.defaultHotkey)?.message
                    }
                    .disabled(settings.hotkey(for: action) == action.defaultHotkey)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("More options for \(action.title)")
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: SettingsWindowController.willClose)) { _ in stop() }
    }

    private var label: String {
        if isRecording { return "Type shortcut…" }
        return settings.display(for: action) ?? "Off"
    }

    private func start() {
        error = nil
        isRecording = true
        settings.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only keys typed in Settings; other windows keep theirs.
            guard event.window?.identifier == SettingsWindowController.identifier else { return event }
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        settings.resume()
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53, flags.isEmpty {  // escape cancels
            stop()
            return
        }
        switch Hotkey.from(event) {
            case .failure(let problem):
                error = problem.message
            case .success(let hotkey):
                if !settings.isAvailable(hotkey) {
                    error = HotkeyError.taken(hotkey.display).message
                    return
                }
                stop()
                error = settings.change(action, to: hotkey)?.message
        }
    }
}
