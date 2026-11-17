//
//  CurrencyPicker.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// A button showing the chosen currency's flag that opens `CurrencyList`:
/// pick one currency, with search.
struct CurrencyPickerButton: View {
    @Binding var selection: String
    /// Off where the flag is already shown next to the button.
    var showsFlag = true
    @State private var isOpen = false
    
    var body: some View {
        let currency = Currency.named(selection) ?? Currency.all[1]
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                if showsFlag {
                    CurrencyFlag(currency: currency, size: 22)
                }
                Text(currency.code)
                    .font(.system(size: showsFlag ? 13 : 15, weight: .semibold))
                Text(currency.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, showsFlag ? 5 : 0)
            .padding(.trailing, showsFlag ? 8 : 0)
            .padding(.vertical, showsFlag ? 4 : 0)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(showsFlag ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            CurrencyList(mode: .single(selection)) { code in
                selection = code
                isOpen = false
            }
        }
        .accessibilityLabel("Currency: \(currency.name)")
    }
}

/// A button that opens `CurrencyList` to choose several currencies.
struct CurrencyChooserButton: View {
    @Binding var chosen: [String]
    @State private var isOpen = false
    
    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            Label("Currencies (\(chosen.count))", systemImage: "plus.circle")
                .font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            CurrencyList(mode: .multiple(Set(chosen))) { code in
                if let index = chosen.firstIndex(of: code) {
                    chosen.remove(at: index)
                } else {
                    chosen.append(code)
                }
            }
        }
        .help("Choose which currencies to show — \(Currency.all.count) available")
    }
}

/// Every currency with its flag, grouped by region, with a search field on
/// top. ↑↓ move, Return picks, Escape closes.
struct CurrencyList: View {
    enum Mode {
        case single(String)
        case multiple(Set<String>)
        
        func isChosen(_ code: String) -> Bool {
            switch self {
                case .single(let selected): selected == code
                case .multiple(let selected): selected.contains(code)
            }
        }
    }
    
    let mode: Mode
    let onPick: (String) -> Void
    
    @State private var query = ""
    @State private var highlighted: String?
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool
    
    /// Matches the code, English or Khmer name, symbol or region.
    private var matches: [Currency] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return Currency.all }
        return Currency.all.filter { currency in
            [currency.code, currency.name, currency.khmerName, currency.symbol, currency.region.rawValue]
                .contains { $0.localizedCaseInsensitiveContains(text) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            list
            if case .multiple(let chosen) = mode {
                Divider()
                Text("\(chosen.count) shown · click to add or remove")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
        }
        .frame(width: 330, height: 400)
        .onAppear {
            searchFocused = true
            if case .single(let selected) = mode { highlighted = selected }
            startKeyMonitor()
        }
        .onDisappear(perform: stopKeyMonitor)
    }
    
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search currency · ស្វែងរក", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onChange(of: query) { _ in highlighted = matches.first?.code }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    private var list: some View {
        let found = matches
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                    if found.isEmpty {
                        Text("No currency matches “\(query)”.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                    ForEach(Currency.Region.allCases, id: \.self) { region in
                        let inRegion = found.filter { $0.region == region }
                        if !inRegion.isEmpty {
                            Section {
                                ForEach(inRegion) { currency in
                                    row(currency).id(currency.code)
                                }
                            } header: {
                                Text(region.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.bar)
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .onAppear {
                if let highlighted { proxy.scrollTo(highlighted, anchor: .center) }
            }
            .onChange(of: highlighted) { code in
                if let code { proxy.scrollTo(code) }
            }
        }
    }
    
    private func row(_ currency: Currency) -> some View {
        let chosen = mode.isChosen(currency.code)
        let isHighlighted = highlighted == currency.code
        return HStack(spacing: 10) {
            if case .multiple = mode {
                Image(systemName: chosen ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
            }
            CurrencyFlag(currency: currency, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(currency.code)
                        .font(.system(size: 13, weight: .semibold))
                    Text(currency.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(currency.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(currency.khmerName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if case .single = mode, chosen {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.16) : .clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { if $0 { highlighted = currency.code } }
        .onTapGesture { onPick(currency.code) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
    
    // MARK: - Keys
    
    /// ↑ and ↓ move the highlight and Return picks, even while the search
    /// field has the keyboard (a text field would otherwise take the arrows).
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated { handleKey(event.keyCode) }
            return consumed ? nil : event
        }
    }
    
    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
    
    private func handleKey(_ keyCode: UInt16) -> Bool {
        let codes = matches.sorted { lhs, rhs in
            let regions = Currency.Region.allCases
            return (regions.firstIndex(of: lhs.region)!, Currency.all.firstIndex(of: lhs)!)
            < (regions.firstIndex(of: rhs.region)!, Currency.all.firstIndex(of: rhs)!)
        }.map(\.code)
        guard !codes.isEmpty else { return false }
        let index = highlighted.flatMap { codes.firstIndex(of: $0) }
        switch keyCode {
            case 125:  // down
                highlighted = codes[min((index ?? -1) + 1, codes.count - 1)]
                return true
            case 126:  // up
                highlighted = codes[max((index ?? codes.count) - 1, 0)]
                return true
            case 36, 76:  // return
                if let highlighted { onPick(highlighted) }
                return true
            default:
                return false
        }
    }
}
