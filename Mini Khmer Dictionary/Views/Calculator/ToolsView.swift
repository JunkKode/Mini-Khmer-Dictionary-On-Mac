//
//  ToolsView.swift
//  Mini Khmer Dictionary
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// The Calculator's tool tabs: everyday Cambodian conversions that don't
/// fit a keypad — money in riel and dollars, numbers in Khmer words, gold and
/// land units, loans, and dates in both calendars.
struct ToolsView: View {
    let tool: Tool
    let onCopy: (String) -> Void
    
    enum Tool: String, CaseIterable, Identifiable {
        case currency, number, units, loan, date
        var id: String { rawValue }
    }
    
    var body: some View {
        Group {
            switch tool {
                case .currency: CurrencyTool(onCopy: onCopy)
                case .number: NumberTool(onCopy: onCopy)
                case .units: UnitsTool(onCopy: onCopy)
                case .loan: LoanTool(onCopy: onCopy)
                case .date: DateTool(onCopy: onCopy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Shared pieces

/// Reads what was typed in a Tools field: a number or an expression, with
/// thousands separators or Khmer digits.
enum ToolsInput {
    private static let engine = FormulaEngine()
    
    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let plain = KhmerNumbers.westernDigits(trimmed).replacingOccurrences(of: ",", with: "")
        if let value = Double(plain) { return value }
        guard let value = engine.calculate(plain).value else { return nil }
        return try? value.asNumber()
    }
    
    /// Rounded to `digits` places, but a tiny non-zero value keeps enough
    /// places to show it (1 ជី is 0.00000375 t, not 0).
    static func format(_ value: Double, digits: Int = 2) -> String {
        var places = digits
        if value != 0, abs(value) < pow(10, -Double(digits)) {
            places = min(12, Int((-log10(abs(value))).rounded(.up)) + 2)
        }
        return FormulaFormatter.display(.number(value), fractionDigits: places)
    }
}

private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// A currency's flag in a circle, from the `flag-XXX` image set in
/// Assets.xcassets, or its symbol in a tinted circle until one is added.
struct CurrencyFlag: View {
    let currency: Currency
    var size: CGFloat = 30
    
    var body: some View {
        Group {
            if let image = NSImage(named: currency.flagAssetName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(tint.opacity(0.18))
                    Text(currency.symbol)
                        .font(.system(size: size * (currency.symbol.count > 1 ? 0.36 : 0.5), weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
    
    /// A steady colour per currency, so the placeholders are told apart.
    private var tint: Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .pink, .indigo, .brown, .mint, .cyan]
        let index = currency.code.unicodeScalars.reduce(0) { $0 + Int($1.value) } % palette.count
        return palette[index]
    }
}

/// A value with a copy button, used for every result in Tools.
private struct ResultRow: View {
    var currency: Currency? = nil
    let label: String
    var detail: String? = nil
    let value: String
    var emphasized = false
    let onCopy: (String) -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: currency == nil ? .firstTextBaseline : .center, spacing: 8) {
            if let currency {
                CurrencyFlag(currency: currency)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: emphasized ? .semibold : .regular))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: emphasized ? 15 : 13, weight: emphasized ? .semibold : .medium, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Button {
                onCopy(value)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(isHovered ? 1 : 0.35)
            .help("Copy \(value)")
            .accessibilityLabel("Copy \(label)")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct NumberField: View {
    let title: String
    @Binding var text: String
    var width: CGFloat? = nil
    
    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, design: .rounded))
            .monospacedDigit()
            .frame(width: width)
    }
}

// MARK: - Currency

@MainActor
private final class RatesModel: ObservableObject {
    @Published private(set) var rates: [String: Double] = [:]
    @Published private(set) var updated: Date?
    @Published private(set) var source: String?
    @Published private(set) var isFetching = false
    @Published private(set) var fetchError: String?
    
    private let store = ExchangeRates.shared
    
    init() { reload() }
    
    func reload() {
        let snapshot = store.snapshot
        rates = snapshot.rates
        updated = snapshot.updated
        source = snapshot.source
    }
    
    func set(_ value: Double, for code: String) {
        store.setRate(value, for: code)
        reload()
    }
    
    func reset() {
        store.resetToDefaults()
        reload()
    }
    
    func fetch() async {
        isFetching = true
        fetchError = nil
        defer { isFetching = false }
        do {
            let latest = try await ExchangeRates.fetchLatest()
            store.apply(latest.rates, updated: latest.updated, source: "open.er-api.com")
            reload()
        } catch {
            fetchError = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach the exchange-rate service. Check your connection; your current rates are unchanged."
        }
    }
}

/// One amount — or a sum mixing currencies, `$12 + 5000៛` — converted into
/// every chosen currency at once.
struct CurrencyTool: View {
    let onCopy: (String) -> Void
    
    @StateObject private var rates = RatesModel()
    @AppStorage("currencyAmount") private var amountText = "100"
    @AppStorage("currencyFrom") private var from = "USD"
    @AppStorage("currencyShown") private var shownList = "KHR,USD,THB,VND,EUR,CNY,JPY,KRW"
    /// Set once the won and the yen have been added to a list saved before
    /// they were shown by default.
    @AppStorage("currencyShownAddedKRW") private var addedKRW = false
    @AppStorage("currencyRoundRiel") private var roundRiel = true
    @State private var showsRates = false
    
    @FocusState private var focused: String?
    /// What has been typed, and in which row. A row starts empty, with its
    /// value in grey behind it; left empty, it keeps that value. Tying the
    /// text to its row matters: clicking from one row straight into another
    /// must not carry the first row's digits into the second.
    @State private var editing = ""
    @State private var editingCode: String?
    /// The row being dragged to a new place.
    @State private var dragging: String?
    
    /// The calculator's springs, so amounts roll the same way.
    private let morphSpring = Animation.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.1)
    private let digitSpring = Animation.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)
    
    /// The chosen currencies, in the order they were added.
    private var shown: [Currency] {
        var seen: Set<String> = []
        return shownList.split(separator: ",").compactMap { code in
            guard seen.insert(String(code)).inserted else { return nil }
            return Currency.named(String(code))
        }
    }
    
    private func setShown(_ codes: [String]) {
        shownList = codes.joined(separator: ",")
    }
    
    /// The amount in US dollars: what was typed in the base row (`from`),
    /// or a sum that names its own currencies.
    private var dollars: Double? {
        if let expression = ExchangeRates.shared.dollarExpression(from: amountText),
           let value = try? FormulaEngine().calculate(expression).value?.asNumber() {
            return value
        }
        guard let amount = ToolsInput.number(amountText), let rate = rates.rates[from] else { return nil }
        return amount / rate
    }
    
    private var isMixed: Bool {
        ExchangeRates.shared.dollarExpression(from: amountText) != nil
    }
    
    /// What `currency`'s row is worth. The row typed in keeps its exact
    /// amount; the others round riel when asked.
    private func amount(in currency: Currency) -> Double? {
        guard let dollars, let rate = rates.rates[currency.code] else { return nil }
        let raw = dollars * rate
        return currency.code == from ? raw : value(raw, in: currency)
    }
    
    /// The amount as the row shows it: grouped digits, the currency's
    /// decimals, no symbol (the code is beside it).
    private func display(_ currency: Currency) -> String {
        guard let amount = amount(in: currency) else { return "" }
        return Self.formatted(
            amount,
            minimumFractionDigits: currency.code == from ? 0 : currency.fractionDigits,
            maximumFractionDigits: currency.fractionDigits
        )
    }
    
    private static func formatted(
        _ value: Double,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int,
        grouped: Bool = true
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        // The POSIX locale has no thousands separator of its own.
        formatter.usesGroupingSeparator = grouped
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
    
    /// `05` → `5`, `007` → `7`, and the same in Khmer digits; `0.5` and a
    /// lone `0` stay as they are.
    static func withoutLeadingZero(_ text: String) -> String {
        let zeros: Set<Character> = ["0", "០"]
        var characters = Array(text)
        while characters.count > 1, zeros.contains(characters[0]),
              characters[1].isNumber {
            characters.removeFirst()
        }
        return String(characters)
    }
    
    /// What a row's field holds when it's clicked: the row typed in keeps
    /// exactly what was typed; any other row its value, without commas, so
    /// it can be edited.
    private func initialText(for code: String) -> String {
        if code == from { return amountText }
        guard let currency = Currency.named(code), let amount = amount(in: currency) else { return "" }
        return Self.formatted(amount, minimumFractionDigits: 0, maximumFractionDigits: currency.fractionDigits, grouped: false)
    }
    
    /// The grey line under the field while typing: the number with its
    /// thousands grouped (1000000 → 1,000,000), or what a sum comes to.
    /// Nothing when it would just repeat what was typed.
    private func preview(for currency: Currency) -> String? {
        let typed = editing.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return nil }
        let plain = KhmerNumbers.westernDigits(typed).replacingOccurrences(of: ",", with: "")
        if let value = Double(plain), plain.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) {
            let decimals = plain.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
            var text = Self.formatted(value, minimumFractionDigits: decimals, maximumFractionDigits: decimals)
            if plain.hasSuffix(".") { text += "." }
            return text == typed ? nil : text
        }
        let total = display(currency)
        return total.isEmpty ? nil : "= \(total)"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(isMixed ? "Adding up mixed currencies in \(from) — numbers without a currency are multipliers." : "Type in any currency · $12 + 5000៛ works too")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Toggle("Round riel to ៛100", isOn: $roundRiel)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.system(size: 11))
                    currencyMenu
                }
                
                VStack(spacing: 6) {
                    ForEach(shown) { currency in
                        row(currency)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .onDrop(of: [.text], delegate: CurrencyRowDropDelegate(
                                code: currency.code,
                                codes: shown.map(\.code),
                                dragging: $dragging,
                                move: { codes in withAnimation(morphSpring) { setShown(codes) } }
                            ))
                    }
                }
                .animation(morphSpring, value: shownList)
                
                ratesSection
            }
            .padding(14)
            // A click anywhere that isn't a row ends the editing.
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { endEditing() })
        }
        .onChange(of: focused) { code in
            // A clicked row keeps its value, ready to edit; see `editing`.
            editing = code.map(initialText(for:)) ?? ""
            editingCode = code
            guard code != nil else { return }
            // Put the cursor at the end rather than selecting everything,
            // so a click never wipes the number.
            DispatchQueue.main.async {
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                }
            }
        }
        .onAppear {
            // An earlier version could save an empty amount; start from 100.
            if dollars == nil { amountText = "100" }
            guard !addedKRW else { return }
            addedKRW = true
            var codes = shown.map(\.code)
            for code in ["JPY", "KRW"] where !codes.contains(code) { codes.append(code) }
            setShown(codes)
        }
    }
    
    /// One currency, XE-style: its flag and code (click to change it), and
    /// an amount you can type in, which makes it the one the others follow.
    /// Ends editing: the focused row keeps what was typed, or goes back to
    /// its value if nothing was.
    private func endEditing() {
        focused = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
    
    private func row(_ currency: Currency) -> some View {
        let isBase = currency.code == from
        let isEditing = focused == currency.code
        // One outline only: the row being typed in, or else the base row.
        let isActive = isEditing || (focused == nil && isBase)
        let rate = rates.rates[currency.code].flatMap { mine in rates.rates[from].map { mine / $0 } }
        let typedPreview = isEditing && editingCode == currency.code ? preview(for: currency) : nil
        let shownAmount = display(currency)
        return HStack(spacing: 10) {
            // The flag and name are the handle for dragging the row to a new
            // place; the rest of the row is the amount field.
            HStack(spacing: 10) {
                CurrencyFlag(currency: currency, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    CurrencyPickerButton(selection: Binding(
                        get: { currency.code },
                        set: { replace(currency.code, with: $0) }
                    ), showsFlag: false)
                    Text(currency.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 192, alignment: .leading)
            .contentShape(Rectangle())
            .onDrag {
                dragging = currency.code
                return NSItemProvider(object: currency.code as NSString)
            }
            .help("Drag to reorder · right-click to delete")
            
            Spacer(minLength: 6)
            
            VStack(alignment: .trailing, spacing: 2) {
                ZStack(alignment: .trailing) {
                    // The field is only seen while typing; otherwise the
                    // amount is plain text, so it can roll to new values
                    // like the calculator's result.
                    TextField("0", text: Binding(
                        get: { isEditing ? (editingCode == currency.code ? editing : initialText(for: currency.code)) : shownAmount },
                        set: { typed in
                            // macOS also pushes the field's text back when focus
                            // comes or goes; only real typing in this row counts.
                            guard focused == currency.code else { return }
                            // Typing after a lone 0 replaces it: 0 then 5 is 5.
                            let text = Self.withoutLeadingZero(typed)
                            if text != typed {
                                // The field doesn't always redraw a value changed
                                // under it; set it directly, cursor at the end.
                                DispatchQueue.main.async {
                                    guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
                                          editor.string == typed else { return }
                                    editor.string = text
                                    editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
                                }
                            }
                            if editingCode != currency.code {
                                // Focus just arrived here: start from this
                                // row's own value, not the row before's.
                                editingCode = currency.code
                                editing = initialText(for: currency.code)
                                return
                            }
                            // Clicking a row doesn't make it the one the
                            // others follow; changing its number does.
                            guard text != editing else { return }
                            editing = text
                            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            from = currency.code
                            amountText = text
                        }
                    ))
                    .onSubmit { endEditing() }
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .focused($focused, equals: currency.code)
                    .opacity(isEditing ? 1 : 0)
                    .accessibilityLabel("Amount in \(currency.name)")
                    
                    if !isEditing {
                        Text(shownAmount.isEmpty ? "0" : shownAmount)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(shownAmount.isEmpty ? Color.secondary : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                            .animation(digitSpring, value: shownAmount)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                
                if let typedPreview {
                    Text(typedPreview)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(digitSpring, value: typedPreview)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .accessibilityLabel("Reads \(typedPreview)")
                }
                
                let subtitleText = subtitle(for: currency, isBase: isBase, rate: rate)
                Text(subtitleText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.interpolate)
                    .animation(morphSpring, value: subtitleText)
            }
            .animation(morphSpring, value: typedPreview == nil)
            
            Button {
                if let amount = amount(in: currency) { onCopy(currency.format(amount)) }
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Copy the amount in \(currency.code)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isActive ? 0.07 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isActive ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { focused = currency.code }
        .animation(.easeOut(duration: 0.15), value: isActive)
        .contextMenu {
            Button("Copy \(currency.code) Amount") {
                if let amount = amount(in: currency) { onCopy(currency.format(amount)) }
            }
            Button("Move to Top") { moveToTop(currency.code) }
                .disabled(shown.first?.code == currency.code)
            Divider()
            Button("Delete \(currency.code)") { remove(currency.code) }
                .disabled(shown.count <= 1)
        }
    }
    
    private func moveToTop(_ code: String) {
        var codes = shown.map(\.code)
        codes.removeAll { $0 == code }
        withAnimation(morphSpring) { setShown([code] + codes) }
    }
    
    /// Takes a currency off the list. When it was the one typed in, the
    /// next row takes over with the same value, so the others don't change.
    private func remove(_ code: String) {
        var codes = shown.map(\.code)
        guard codes.count > 1 else { return }
        if focused == code { endEditing() }
        if code == from, let next = codes.first(where: { $0 != code }) {
            let value = initialText(for: next)
            from = next
            if !value.isEmpty { amountText = value }
        }
        codes.removeAll { $0 == code }
        withAnimation(morphSpring) { setShown(codes) }
    }
    
    private func subtitle(for currency: Currency, isBase: Bool, rate: Double?) -> String {
        if isBase {
            if let amount = amount(in: currency), currency.code == "KHR" || currency.code == "USD",
               let words = KhmerNumbers.moneyWords(for: amount, currency: currency) {
                return words
            }
            return "Converting from \(currency.code)"
        }
        guard let rate else { return "" }
        return "1 \(from) → \(ToolsInput.format(rate, digits: 4)) \(currency.code)"
    }
    
    /// A row's currency changed from its drop-down: swap it in place.
    private func replace(_ old: String, with new: String) {
        guard old != new else { return }
        var codes = shown.map(\.code)
        if let existing = codes.firstIndex(of: new) { codes.remove(at: existing) }
        if let index = codes.firstIndex(of: old) { codes[index] = new } else { codes.append(new) }
        setShown(codes)
        if from == old { from = new }
    }
    
    private func value(_ amount: Double, in currency: Currency) -> Double {
        guard currency.code == "KHR", roundRiel else { return amount }
        return (amount / 100).rounded() * 100
    }
    
    /// Which currencies to convert into: a searchable list with flags. New
    /// ones go at the bottom.
    private var currencyMenu: some View {
        CurrencyChooserButton(chosen: Binding(
            get: { shown.map(\.code) },
            set: { codes in
                let kept = shown.map(\.code).filter(codes.contains)
                setShown(kept + codes.filter { !kept.contains($0) })
                if !codes.contains(from), let first = codes.first { from = first }
            }
        ))
    }
    
    private var ratesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showsRates.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(showsRates ? 90 : 0))
                        SectionLabel("Exchange rates")
                    }
                }
                .buttonStyle(.plain)
                
                Text(rateStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if rates.isFetching {
                    ProgressView().controlSize(.small)
                }
                Button("Update Online") { Task { await rates.fetch() } }
                    .controlSize(.small)
                    .disabled(rates.isFetching)
                    .help("Fetch today's market rates (from open.er-api.com, no account needed)")
            }
            if let error = rates.fetchError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            if showsRates {
                VStack(spacing: 4) {
                    ForEach(Currency.all.filter { $0.code != "USD" }) { currency in
                        RateRow(currency: currency, rate: rates.rates[currency.code] ?? 0) { rates.set($0, for: currency.code) }
                    }
                    HStack {
                        Text("Market rates differ from the National Bank of Cambodia's official riel rate; set it by hand if you need that one.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Reset") { rates.reset() }
                            .controlSize(.small)
                    }
                }
                .transition(.opacity)
            }
        }
    }
    
    private var rateStatus: String {
        let riel = rates.rates["KHR"].map { "1 USD = \(Currency.named("KHR")!.format($0))" } ?? ""
        guard let updated = rates.updated else {
            return riel + (rates.source == nil ? " · starting rates" : " · set by hand")
        }
        let when = updated.formatted(date: .abbreviated, time: .shortened)
        return riel + " · \(rates.source ?? "updated") \(when)"
    }
}

private struct RateRow: View {
    let currency: Currency
    let rate: Double
    let onChange: (Double) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Text("1 USD =")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Rate", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .monospacedDigit()
                .frame(width: 110)
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) { focused in if !focused { commit() } }
            CurrencyFlag(currency: currency, size: 16)
            Text("\(currency.code) · \(currency.name)")
                .font(.system(size: 11))
            Spacer()
        }
        .onAppear { text = FormulaFormatter.plain(rate) }
        .onChange(of: rate) { value in if !isFocused { text = FormulaFormatter.plain(value) } }
    }
    
    private func commit() {
        if let value = ToolsInput.number(text), value > 0 {
            onChange(value)
        } else {
            text = FormulaFormatter.plain(rate)
        }
    }
}

// MARK: - Khmer number

private struct NumberTool: View {
    let onCopy: (String) -> Void
    @AppStorage("khmerNumberInput") private var text = "1250000"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Number")
                NumberField(title: "1250000   or   ១២៥០០០០   or   25 * 1500", text: $text)
            }
            if let value = ToolsInput.number(text) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Written out")
                    if let words = KhmerNumbers.words(for: value) {
                        ResultRow(label: "In words", value: words, emphasized: true, onCopy: onCopy)
                    }
                    ResultRow(label: "Khmer digits", value: KhmerNumbers.digits(ToolsInput.format(value, digits: 6)), onCopy: onCopy)
                    if let riel = KhmerNumbers.moneyWords(for: value, currency: Currency.named("KHR")!) {
                        ResultRow(label: "As riel", detail: Currency.named("KHR")!.format(value.rounded()), value: riel, onCopy: onCopy)
                    }
                    if let dollars = KhmerNumbers.moneyWords(for: value, currency: Currency.named("USD")!) {
                        ResultRow(label: "As dollars", detail: Currency.named("USD")!.format(value), value: dollars, onCopy: onCopy)
                    }
                    ResultRow(label: "Western digits", value: ToolsInput.format(value, digits: 6), onCopy: onCopy)
                }
                Text("Below a million, amounts are counted in សែន (100,000) and ម៉ឺន (10,000), the way prices are said. Also in formulas: =KHMERWORDS(…), =KHMERMONEY(…, \"USD\").")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !text.isEmpty {
                Text("That isn't a number.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Units and gold

private struct UnitsTool: View {
    let onCopy: (String) -> Void
    
    @AppStorage("unitsCategory") private var category: MeasureCategory = .weight
    @AppStorage("unitsInput") private var text = "1"
    @AppStorage("unitsFrom") private var fromID = "chi"
    @AppStorage("goldPrice") private var goldPriceText = ""
    @AppStorage("goldPriceUnit") private var goldPriceUnit = "damlung"
    @AppStorage("goldCurrency") private var goldCurrency = "USD"
    
    private var from: MeasureUnit {
        category.units.first { $0.id == fromID } ?? category.units[0]
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Kind", selection: $category) {
                    ForEach(MeasureCategory.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .onChange(of: category) { newValue in
                    if !newValue.units.contains(where: { $0.id == fromID }) { fromID = newValue.units[0].id }
                }
                
                HStack(spacing: 8) {
                    NumberField(title: "Amount", text: $text)
                    Picker("From", selection: $fromID) {
                        ForEach(category.units) { unit in
                            Text("\(unit.khmerName) · \(unit.name)").tag(unit.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                
                if let value = ToolsInput.number(text) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(category.units.filter { $0.id != from.id }) { unit in
                            ResultRow(
                                label: "\(unit.khmerName) · \(unit.name)",
                                detail: unit.isTraditional ? "Traditional unit; sizes vary by place" : nil,
                                value: ToolsInput.format(category.convert(value, from: from, to: unit), digits: 4),
                                onCopy: onCopy
                            )
                        }
                    }
                    if category == .weight {
                        gold(grams: value * from.factor)
                    }
                }
            }
            .padding(14)
        }
    }
    
    @ViewBuilder
    private func gold(grams: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            SectionLabel("Gold value")
            HStack(spacing: 8) {
                NumberField(title: "Price", text: $goldPriceText, width: 120)
                Picker("Currency", selection: $goldCurrency) {
                    Text("USD").tag("USD")
                    Text("KHR").tag("KHR")
                }
                .labelsHidden()
                .frame(width: 72)
                Picker("Per", selection: $goldPriceUnit) {
                    Text("per ដំឡឹង").tag("damlung")
                    Text("per ជី").tag("chi")
                    Text("per troy ounce").tag("ozt")
                }
                .labelsHidden()
                .frame(width: 130)
            }
            let breakdown = GoldWeight.breakdown(grams: grams).map { "\(KhmerNumbers.digits(String($0.count)))\($0.unit)" }.joined(separator: " ")
            if !breakdown.isEmpty {
                ResultRow(label: "Weight", detail: "\(ToolsInput.format(grams, digits: 4)) g", value: breakdown, onCopy: onCopy)
            }
            if let price = ToolsInput.number(goldPriceText), let currency = Currency.named(goldCurrency) {
                let perDamlung: Double = switch goldPriceUnit {
                    case "chi": price * 10
                    case "ozt": GoldWeight.damlungPrice(fromOuncePrice: price)
                    default: price
                }
                ResultRow(label: "Worth", value: currency.format(GoldWeight.value(grams: grams, pricePerDamlung: perDamlung)), emphasized: true, onCopy: onCopy)
                if goldPriceUnit == "ozt" {
                    ResultRow(label: "Price per ដំឡឹង", value: currency.format(perDamlung), onCopy: onCopy)
                }
            } else {
                Text("Enter today's gold price to see what this weight is worth. 1 ដំឡឹង = 10 ជី = 37.5 g.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Loan

private struct LoanTool: View {
    let onCopy: (String) -> Void
    
    @AppStorage("loanAmount") private var amountText = "5000"
    @AppStorage("loanRate") private var rateText = "1.5"
    @AppStorage("loanRatePerMonth") private var ratePerMonth = true
    @AppStorage("loanMonths") private var monthsText = "24"
    @AppStorage("loanMethod") private var method: LoanMethod = .equalPrincipal
    @AppStorage("loanCurrency") private var currencyCode = "USD"
    
    private var currency: Currency { Currency.named(currencyCode) ?? Currency.all[1] }
    
    private var schedule: LoanSchedule? {
        guard let principal = ToolsInput.number(amountText), let rate = ToolsInput.number(rateText),
              let months = ToolsInput.number(monthsText) else { return nil }
        let monthly = ratePerMonth ? rate / 100 : rate / 100 / 12
        let result = LoanSchedule(principal: principal, monthlyRate: monthly, months: Int(months.rounded()), method: method)
        return result.rows.isEmpty ? nil : result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    label("Amount")
                    HStack(spacing: 6) {
                        NumberField(title: "5000", text: $amountText, width: 130)
                        Picker("Currency", selection: $currencyCode) {
                            Text("USD").tag("USD")
                            Text("KHR").tag("KHR")
                            Text("THB").tag("THB")
                        }
                        .labelsHidden()
                        .frame(width: 72)
                    }
                }
                GridRow {
                    label("Interest")
                    HStack(spacing: 6) {
                        NumberField(title: "1.5", text: $rateText, width: 70)
                        Text("%").foregroundStyle(.secondary)
                        Picker("Per", selection: $ratePerMonth) {
                            Text("per month").tag(true)
                            Text("per year").tag(false)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }
                GridRow {
                    label("Term")
                    HStack(spacing: 6) {
                        NumberField(title: "24", text: $monthsText, width: 70)
                        Text("months").foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    label("Repayment")
                    Picker("Method", selection: $method) {
                        ForEach(LoanMethod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
            }
            .font(.system(size: 12))
            
            if let schedule {
                HStack(spacing: 0) {
                    summary(method == .equalPayments ? "Monthly" : "First payment", currency.format(schedule.firstPayment))
                    if method == .equalPrincipal {
                        summary("Last payment", currency.format(schedule.lastPayment))
                    }
                    summary("Total interest", currency.format(schedule.totalInterest))
                    summary("Total paid", currency.format(schedule.totalPaid))
                }
                scheduleTable(schedule)
            } else {
                Text("Enter an amount, a rate and a number of months.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }
    
    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }
    
    private func summary(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func scheduleTable(_ schedule: LoanSchedule) -> some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel("Schedule")
                Spacer()
                Button("Copy Table") {
                    let header = "Month\tPayment\tPrincipal\tInterest\tBalance"
                    let rows = schedule.rows.map { row in
                        [String(row.month), FormulaFormatter.plain(round2(row.payment)), FormulaFormatter.plain(round2(row.principal)),
                         FormulaFormatter.plain(round2(row.interest)), FormulaFormatter.plain(round2(row.balance))].joined(separator: "\t")
                    }
                    onCopy(([header] + rows).joined(separator: "\n"))
                }
                .controlSize(.small)
                .help("Copy as rows that paste into the Grid, Numbers or Excel")
            }
            .padding(.bottom, 4)
            HStack {
                ForEach(["#", "Payment", "Principal", "Interest", "Balance"], id: \.self) { title in
                    Text(title).frame(maxWidth: .infinity, alignment: title == "#" ? .leading : .trailing)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Color.primary.opacity(0.05))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(schedule.rows) { row in
                        HStack {
                            Text("\(row.month)").frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.secondary)
                            Text(currency.format(row.payment)).frame(maxWidth: .infinity, alignment: .trailing)
                            Text(currency.format(row.principal)).frame(maxWidth: .infinity, alignment: .trailing)
                            Text(currency.format(row.interest)).frame(maxWidth: .infinity, alignment: .trailing)
                            Text(currency.format(row.balance)).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(row.month % 2 == 0 ? Color.primary.opacity(0.03) : .clear)
                    }
                }
            }
        }
    }
    
    private func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

// MARK: - Date

private struct DateTool: View {
    let onCopy: (String) -> Void
    
    @State private var lunarDate = Date()
    @State private var start = Date()
    @State private var end = DateMath.adding(days: 30, to: Date())
    @State private var offsetText = "30"
    @State private var offsetUnit = "days"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Khmer calendar")
                    DatePicker("Date", selection: $lunarDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .frame(width: 140)
                    if let both = KhmerDateText.lunarAndSolar(lunarDate) {
                        ResultRow(label: "Lunar + Solar", value: both, emphasized: true, onCopy: onCopy)
                    }
                    ResultRow(label: "Solar", value: DateMath.khmerSolarDate(lunarDate), onCopy: onCopy)
                    if let lunar = KhmerLunarCalendar.date(for: lunarDate) {
                        ResultRow(
                            label: "Lunar",
                            detail: lunar.isHolyDay ? "ថ្ងៃសីល — Buddhist holy day" : nil,
                            value: lunar.fullText,
                            onCopy: onCopy
                        )
                    } else {
                        Text("The lunar calendar covers \(KhmerLunarCalendar.supportedYears.lowerBound)–\(KhmerLunarCalendar.supportedYears.upperBound).")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text("Animal year and ស័ក turn at Khmer New Year (taken as 14 April).")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Between two dates")
                    HStack(spacing: 8) {
                        DatePicker("From", selection: $start, displayedComponents: .date).datePickerStyle(.field).frame(width: 150)
                        DatePicker("to", selection: $end, displayedComponents: .date).datePickerStyle(.field).frame(width: 130)
                    }
                    .font(.system(size: 12))
                    let days = DateMath.days(from: start, to: end)
                    let span = DateMath.span(from: start, to: end)
                    ResultRow(label: "Days", value: "\(days)", emphasized: true, onCopy: onCopy)
                    ResultRow(label: "Years, months, days", value: "\(span.years) y \(span.months) m \(span.days) d", onCopy: onCopy)
                    ResultRow(label: "Weeks", value: ToolsInput.format(Double(abs(days)) / 7, digits: 1), onCopy: onCopy)
                    ResultRow(label: "Working days (Mon–Fri)", detail: "Public holidays aren't excluded", value: "\(DateMath.workingDays(from: start, to: end))", onCopy: onCopy)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Add or subtract")
                    HStack(spacing: 8) {
                        Text(start.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12))
                        Text("+").foregroundStyle(.secondary)
                        NumberField(title: "30", text: $offsetText, width: 70)
                        Picker("Unit", selection: $offsetUnit) {
                            Text("days").tag("days")
                            Text("months").tag("months")
                            Text("years").tag("years")
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    if let offset = ToolsInput.number(offsetText).map({ Int($0.rounded()) }) {
                        let result = DateMath.adding(
                            days: offsetUnit == "days" ? offset : 0,
                            months: offsetUnit == "months" ? offset : 0,
                            years: offsetUnit == "years" ? offset : 0,
                            to: start
                        )
                        ResultRow(label: "Date", value: result.formatted(date: .complete, time: .omitted), emphasized: true, onCopy: onCopy)
                        ResultRow(label: "In Khmer", value: DateMath.khmerSolarDate(result), onCopy: onCopy)
                        if let lunar = KhmerLunarCalendar.date(for: result) {
                            ResultRow(label: "Lunar", value: lunar.dayAndMonth, onCopy: onCopy)
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}

/// Moves a currency row as it's dragged over the others.
private struct CurrencyRowDropDelegate: DropDelegate {
    let code: String
    let codes: [String]
    @Binding var dragging: String?
    let move: ([String]) -> Void
    
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != code,
              let source = codes.firstIndex(of: dragging),
              let target = codes.firstIndex(of: code) else { return }
        var reordered = codes
        reordered.move(fromOffsets: IndexSet(integer: source), toOffset: target > source ? target + 1 : target)
        move(reordered)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil
    }
    
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
