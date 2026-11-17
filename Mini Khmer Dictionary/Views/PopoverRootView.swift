//
//  PopoverRootView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// Switches the popover between looking words up, checking text and
/// calculating.
struct PopoverRootView: View {
    @ObservedObject var dictionary: DictionaryModel
    @ObservedObject var checker: SpellCheckModel
    @ObservedObject var calculator: CalculatorModel
    @ObservedObject var calendar: CalendarModel
    @AppStorage(AppTheme.storageKey) private var themeName = AppTheme.system.rawValue
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                ViewThatFits(in: .horizontal) {
                    PopoverTabBar(selection: $dictionary.mode, labels: .full)
                    PopoverTabBar(selection: $dictionary.mode, labels: .short)
                    PopoverTabBar(selection: $dictionary.mode, labels: .icons)
                }
                Spacer(minLength: 0)
                themeMenu
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .help("⌘1 Look Up · ⌘2 Check Spelling · ⌘3 Calculator · ⌘4 Calendar · ⌘5 Currency · ⌘6 Khmer No. · ⌘7 Gold & Units · ⌘8 Loan · ⌘9 Date")
            
            Divider()
            
            switch dictionary.mode {
                case .lookUp:
                    DictionaryPopoverView(model: dictionary)
                case .check:
                    SpellCheckView(model: checker, onLookUp: dictionary.lookUp)
                case .calculate:
                    CalculatorView(model: calculator)
                case .calendar:
                    CalendarView(model: calendar, onCopy: calculator.copy)
                        .overlay(alignment: .bottom) { copyToast }
                case .currency, .number, .units, .loan, .date:
                    if let tool = dictionary.mode.tool {
                        ToolsView(tool: tool, onCopy: calculator.copy)
                            .overlay(alignment: .bottom) { copyToast }
                    }
            }
        }
        .frame(width: 620, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var themeMenu: some View {
        Menu {
            Picker("Appearance", selection: Binding(
                get: { AppTheme(rawValue: themeName) ?? .system },
                set: { AppTheme.choose($0); themeName = $0.rawValue }
            )) {
                ForEach(AppTheme.allCases) { theme in
                    Label(theme.title, systemImage: theme.icon).tag(theme)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: (AppTheme(rawValue: themeName) ?? .system).icon)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Appearance: \((AppTheme(rawValue: themeName) ?? .system).title)")
        .accessibilityLabel("Appearance")
    }
    
    @ViewBuilder
    private var copyToast: some View {
        if let copied = calculator.copiedText {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Copied").foregroundStyle(.secondary)
                Text(copied).fontWeight(.medium).lineLimit(1)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08)) }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: 0.18), value: calculator.copiedText)
            .accessibilityHidden(true)
        }
    }
}

/// The popover's tabs. Drawn in SwiftUI rather than with a segmented
/// control: the control, nested in the popover, could keep showing an old
/// tab as selected. Here the highlight is read straight from `selection`, and
/// slides to the tab picked.
struct PopoverTabBar: View {
    @Binding var selection: PopoverMode
    let labels: Labels
    
    enum Labels { case full, short, icons }
    
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(PopoverMode.allCases, id: \.self) { mode in
                tab(mode)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
        .fixedSize()
    }
    
    private func tab(_ mode: PopoverMode) -> some View {
        let isSelected = mode == selection
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85)) {
                selection = mode
            }
        } label: {
            Group {
                switch labels {
                    case .full: Text(mode.title)
                    case .short: Text(mode.shortTitle)
                    case .icons: Image(systemName: mode.icon)
                }
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, labels == .icons ? 9 : 8)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "selected", in: highlight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.title)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
