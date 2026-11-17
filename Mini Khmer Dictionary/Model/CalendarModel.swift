//
//  CalendarModel.swift
//  Mini Khmer Dictionary
//

import AppKit
import Combine

/// The Calendar tab: which month is showing, the day picked, and Google's
/// Cambodian holiday list kept up to date in the background.
@MainActor
final class CalendarModel: ObservableObject {
    @Published private(set) var month: (year: Int, month: Int) {
        didSet { if month != oldValue { rebuildMonth() } }
    }
    @Published var selected: CalendarDay
    /// Google's public holidays by day, from the cached calendar file.
    @Published private(set) var google: [CalendarDay: [String]] = [:] {
        didSet { rebuildMonth() }
    }
    /// The showing month laid out, worked out once per month rather than on
    /// every redraw — clicking a day only moves the selection.
    @Published private(set) var monthDays: [KhmerMonthDay] = []
    /// The month's holidays and observances, for the list.
    @Published private(set) var monthEvents: [KhmerMonthDay] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var syncError: String?
    
    /// Google's public "Holidays in Cambodia" calendar. Read-only, no
    /// account needed; nothing about the user is sent.
    static let feedURL = URL(string: "https://calendar.google.com/calendar/ical/en.kh%23holiday%40group.v.calendar.google.com/public/basic.ics")!
    /// Refresh at most this often; holidays are announced months ahead.
    private static let refreshInterval: TimeInterval = 7 * 86_400
    
    init() {
        let today = CalendarDay(Date())
        month = (today.year, today.month)
        selected = today
        loadCache()
        rebuildMonth()
    }
    
    private func rebuildMonth() {
        monthDays = KhmerMonth.days(year: month.year, month: month.month, google: google)
        monthEvents = KhmerMonth.events(in: monthDays)
    }
    
    var today: CalendarDay { CalendarDay(Date()) }
    
    func holidays(on day: CalendarDay) -> [KhmerHoliday] {
        KhmerHolidays.holidays(on: day, google: google)
    }
    
    /// Whether Google's list covers the showing year.
    var googleCoversMonth: Bool {
        google.keys.contains { $0.year == month.year }
    }
    
    // MARK: - Moving
    
    func showMonth(offset: Int) {
        let calendar = KhmerDateText.calendar
        let first = CalendarDay(year: month.year, month: month.month, day: 1).date()
        let moved = CalendarDay(calendar.date(byAdding: .month, value: offset, to: first)!)
        month = (moved.year, moved.month)
        // Keep the same day of the month selected where it exists.
        let days = calendar.range(of: .day, in: .month, for: moved.date())?.count ?? 28
        selected = CalendarDay(year: moved.year, month: moved.month, day: min(selected.day, days))
    }
    
    func goToToday() {
        select(today)
    }
    
    func select(_ day: CalendarDay) {
        selected = day
        if (day.year, day.month) != (month.year, month.month) { month = (day.year, day.month) }
    }
    
    /// Arrow keys move the selection; Page Up/Down change month.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
            case 123: select(selected.adding(days: -1))
            case 124: select(selected.adding(days: 1))
            case 125: select(selected.adding(days: 7))
            case 126: select(selected.adding(days: -7))
            case 116: showMonth(offset: -1)  // page up
            case 121: showMonth(offset: 1)   // page down
            case 115: goToToday()            // home
            default: return false
        }
        return true
    }
    
    // MARK: - Google holidays
    
    private var cacheURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("Holidays", isDirectory: true).appendingPathComponent("google-kh.ics")
    }
    
    private func loadCache() {
        guard let url = cacheURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        google = ICalendarReader.allDayEvents(in: text)
        lastSync = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
    
    /// Fetches Google's list if the copy on disk is missing or a week old.
    func refreshIfNeeded() async {
        if let lastSync, Date().timeIntervalSince(lastSync) < Self.refreshInterval { return }
        await sync()
    }
    
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.feedURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            let events = ICalendarReader.allDayEvents(in: text)
            guard !events.isEmpty else { throw URLError(.cannotParseResponse) }
            google = events
            lastSync = Date()
            if let url = cacheURL {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            syncError = "Couldn't reach Google Calendar. Showing calculated holidays\(google.isEmpty ? "" : " and the last copy synced")."
        }
    }
}
