//
//  AppTheme.swift
//  Mini Khmer Dictionary
//

import AppKit

/// Light, dark, or whatever macOS is set to. Chosen from the popover's top
/// bar or the menu bar icon's menu, and kept across launches.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    
    static let storageKey = "appTheme"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
            case .system: "Match System"
            case .light: "Light"
            case .dark: "Dark"
        }
    }
    
    var icon: String {
        switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max"
            case .dark: "moon"
        }
    }
    
    static var current: AppTheme {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppTheme.init) ?? .system
    }
    
    /// The appearance to force, or `nil` to follow macOS.
    var appearance: NSAppearance? {
        switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
        }
    }
    
    /// Posted after a theme is applied, so the popover can follow: it hangs
    /// off the menu bar icon and takes the menu bar's appearance, not the
    /// app's, unless it is given one of its own.
    static let didChange = Notification.Name("AppThemeDidChange")
    
    /// Applies to the app's windows, and (through `didChange`) the popover.
    @MainActor
    func apply() {
        NSApp.appearance = appearance
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    
    @MainActor
    static func choose(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: storageKey)
        theme.apply()
    }
}
