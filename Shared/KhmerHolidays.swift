//
//  KhmerHolidays.swift
//  Mini Khmer Dictionary
//
//  Shared by the app and the Khmer Calendar widget. Foundation only; tested
//  by Tools/test_formula_engine.sh.
//

import Foundation

/// A Gregorian calendar day, by its fields, so time zones never move it.
nonisolated struct CalendarDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = KhmerDateText.calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    func date(calendar: Calendar = KhmerDateText.calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func adding(days: Int, calendar: Calendar = KhmerDateText.calendar) -> CalendarDay {
        CalendarDay(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar))!, calendar: calendar)
    }

    /// `20261115`, as in iCalendar files.
    init?(compact: String) {
        guard compact.count == 8, let y = Int(compact.prefix(4)), let m = Int(compact.dropFirst(4).prefix(2)),
              let d = Int(compact.suffix(2)) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// A holiday or Buddhist observance on one day.
nonisolated struct KhmerHoliday: Hashable, Sendable {
    /// The same holiday from either source shares a key: `visakBochea`.
    let key: String
    let name: String
    let khmerName: String
    /// Days off work, as opposed to observances such as Meak Bochea.
    let isPublic: Bool
    var source: Source
    /// Set when the sources disagree, to say how.
    var note: String?

    enum Source: String, Sendable {
        /// Worked out here from the Khmer calendar and the law's fixed dates.
        case calculated
        /// Only in Google's Cambodian holiday calendar (often a special day
        /// the government announced).
        case google
        /// Google lists it on the day the Khmer calendar gives: confirmed.
        case both
    }
}

/// Cambodian public holidays and Buddhist observances.
///
/// Two sources, used together:
/// - **Calculated**: fixed-date holidays from the law, and the lunar ones
///   (Visak Bochea, Pchum Ben, Water Festival …) from `KhmerLunarCalendar`.
///   Works offline and for any year from 1900 to 2200.
/// - **Google**: Google's public "Holidays in Cambodia" calendar, which
///   follows the government's yearly announcements, including special days
///   off. For years it covers, it decides which days are public holidays.
///
/// Where both name the same holiday on the same day it is confirmed; where
/// they disagree, both are shown with a note.
nonisolated enum KhmerHolidays {
    private struct Rule {
        let key: String
        let name: String
        let khmerName: String
        var isPublic = true
    }

    private static let fixed: [(month: Int, day: Int, rule: Rule)] = [
        (1, 1, Rule(key: "newYear", name: "International New Year", khmerName: "ទិវាចូលឆ្នាំសកល")),
        (1, 7, Rule(key: "victoryDay", name: "Victory over Genocide Day", khmerName: "ទិវាជ័យជម្នះលើរបបប្រល័យពូជសាសន៍")),
        (3, 8, Rule(key: "womensDay", name: "International Women's Day", khmerName: "ទិវានារីអន្តរជាតិ")),
        (4, 14, Rule(key: "khmerNewYear", name: "Khmer New Year (Day 1)", khmerName: "បុណ្យចូលឆ្នាំខ្មែរ (ថ្ងៃទី១)")),
        (4, 15, Rule(key: "khmerNewYear", name: "Khmer New Year (Day 2)", khmerName: "បុណ្យចូលឆ្នាំខ្មែរ (ថ្ងៃទី២)")),
        (4, 16, Rule(key: "khmerNewYear", name: "Khmer New Year (Day 3)", khmerName: "បុណ្យចូលឆ្នាំខ្មែរ (ថ្ងៃទី៣)")),
        (5, 1, Rule(key: "labourDay", name: "International Labour Day", khmerName: "ទិវាពលកម្មអន្តរជាតិ")),
        (5, 14, Rule(key: "kingsBirthday", name: "King's Birthday", khmerName: "ព្រះរាជពិធីបុណ្យចម្រើនព្រះជន្មព្រះមហាក្សត្រ")),
        (6, 18, Rule(key: "queenMothersBirthday", name: "King's Mother's Birthday", khmerName: "ព្រះរាជពិធីបុណ្យចម្រើនព្រះជន្មព្រះវររាជមាតា")),
        (9, 24, Rule(key: "constitutionDay", name: "Constitution Day", khmerName: "ទិវាប្រកាសរដ្ឋធម្មនុញ្ញ")),
        (10, 15, Rule(key: "kingFatherDay", name: "Commemoration Day of King's Father", khmerName: "ទិវាប្រារព្ធពិធីគោរពព្រះវិញ្ញាណក្ខន្ធព្រះបរមរតនកោដ្ឋ")),
        (10, 29, Rule(key: "coronationDay", name: "King's Coronation Day", khmerName: "ព្រះរាជពិធីគ្រងព្រះបរមរាជសម្បត្តិ")),
        (11, 9, Rule(key: "independenceDay", name: "Independence Day", khmerName: "ពិធីបុណ្យឯករាជ្យជាតិ")),
        (12, 29, Rule(key: "peaceDay", name: "Peace Day", khmerName: "ទិវាសន្តិភាពនៅកម្ពុជា")),
    ]

    /// Lunar holidays by (month, day index 0–29 where 0–14 are ១–១៥កើត).
    private static let lunar: [(month: KhmerLunarCalendar.Month, day: Int, rule: Rule)] = [
        (.meak, 14, Rule(key: "meakBochea", name: "Meak Bochea", khmerName: "ពិធីបុណ្យមាឃបូជា", isPublic: false)),
        (.pisak, 14, Rule(key: "visakBochea", name: "Visak Bochea", khmerName: "ពិធីបុណ្យវិសាខបូជា")),
        (.pisak, 18, Rule(key: "royalPloughing", name: "Royal Ploughing Ceremony", khmerName: "ព្រះរាជពិធីច្រត់ព្រះនង្គ័ល")),
        (.phatrabot, 28, Rule(key: "pchumBen", name: "Pchum Ben (Day 1)", khmerName: "ពិធីបុណ្យភ្ជុំបិណ្ឌ (ថ្ងៃទី១)")),
        (.phatrabot, 29, Rule(key: "pchumBen", name: "Pchum Ben (Day 2)", khmerName: "ពិធីបុណ្យភ្ជុំបិណ្ឌ (ថ្ងៃទី២)")),
        (.assoch, 0, Rule(key: "pchumBen", name: "Pchum Ben (Day 3)", khmerName: "ពិធីបុណ្យភ្ជុំបិណ្ឌ (ថ្ងៃទី៣)")),
        (.kadeuk, 13, Rule(key: "waterFestival", name: "Water Festival (Day 1)", khmerName: "ព្រះរាជពិធីបុណ្យអុំទូក (ថ្ងៃទី១)")),
        (.kadeuk, 14, Rule(key: "waterFestival", name: "Water Festival (Day 2)", khmerName: "ព្រះរាជពិធីបុណ្យអុំទូក (ថ្ងៃទី២)")),
        (.kadeuk, 15, Rule(key: "waterFestival", name: "Water Festival (Day 3)", khmerName: "ព្រះរាជពិធីបុណ្យអុំទូក (ថ្ងៃទី៣)")),
    ]

    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var years: [Int: [CalendarDay: [KhmerHoliday]]] = [:]
    }

    /// Every calculated holiday in `year`.
    static func calculated(year: Int) -> [CalendarDay: [KhmerHoliday]] {
        if let known = cache.lock.withLock({ cache.years[year] }) { return known }
        var result: [CalendarDay: [KhmerHoliday]] = [:]
        func add(_ rule: Rule, on day: CalendarDay) {
            result[day, default: []].append(
                KhmerHoliday(key: rule.key, name: rule.name, khmerName: rule.khmerName, isPublic: rule.isPublic, source: .calculated)
            )
        }
        for (month, day, rule) in fixed {
            add(rule, on: CalendarDay(year: year, month: month, day: day))
        }
        if KhmerLunarCalendar.supportedYears.contains(year) {
            var day = CalendarDay(year: year, month: 1, day: 1)
            while day.year == year {
                if let lunar = KhmerLunarCalendar.lunarDay(year: day.year, month: day.month, day: day.day) {
                    for entry in Self.lunar where entry.month == lunar.month && entry.day == lunar.day {
                        add(entry.rule, on: day)
                    }
                }
                day = day.adding(days: 1)
            }
        }
        cache.lock.withLock { cache.years[year] = result }
        return result
    }

    /// Holidays on `day`, merging Google's list when it covers the year.
    /// `google` maps days to the holiday names Google gives.
    static func holidays(on day: CalendarDay, google: [CalendarDay: [String]] = [:]) -> [KhmerHoliday] {
        let calculated = calculated(year: day.year)[day] ?? []
        let googleCoversYear = !google.isEmpty && google.keys.contains { $0.year == day.year }
        guard googleCoversYear else { return calculated }

        var result: [KhmerHoliday] = []
        var matched: Set<String> = []
        for name in google[day] ?? [] {
            let key = canonicalKey(forGoogleName: name)
            if let mine = calculated.first(where: { $0.key == key && !matched.contains($0.name) }) {
                var confirmed = mine
                confirmed.source = .both
                result.append(confirmed)
                matched.insert(mine.name)
            } else {
                // Google's own day: a special day off, or one it moved.
                var holiday = KhmerHoliday(key: key ?? name, name: name, khmerName: khmerName(forGoogleName: name),
                                           isPublic: true, source: .google)
                if let key, let elsewhere = calculatedDays(of: key, in: day.year).first(where: { $0 != day }) {
                    holiday.note = "The Khmer calendar puts this on \(elsewhere.year)-\(elsewhere.month)-\(elsewhere.day)"
                }
                result.append(holiday)
            }
        }
        for holiday in calculated where !matched.contains(holiday.name) {
            var unconfirmed = holiday
            if holiday.isPublic {
                let googleDays = google.filter { $0.key.year == day.year && $0.value.contains { canonicalKey(forGoogleName: $0) == holiday.key } }.keys.sorted()
                unconfirmed.note = googleDays.isEmpty
                    ? "Not in Google's list of public holidays for \(day.year)"
                    : "Google lists it on \(googleDays.map { "\($0.month)/\($0.day)" }.joined(separator: ", "))"
            }
            result.append(unconfirmed)
        }
        return result
    }

    private static func calculatedDays(of key: String, in year: Int) -> [CalendarDay] {
        calculated(year: year).filter { $0.value.contains { $0.key == key } }.keys.sorted()
    }

    /// The key of the calculated holiday Google's English name refers to.
    static func canonicalKey(forGoogleName name: String) -> String? {
        let lower = name.lowercased()
        let table: [(String, String)] = [
            ("khmer new year", "khmerNewYear"), ("new year", "newYear"), ("genocide", "victoryDay"),
            ("women", "womensDay"), ("labour", "labourDay"), ("labor", "labourDay"),
            ("king's mother", "queenMothersBirthday"), ("queen mother", "queenMothersBirthday"),
            ("king's father", "kingFatherDay"), ("coronation", "coronationDay"), ("king's birthday", "kingsBirthday"),
            ("constitution", "constitutionDay"), ("independence", "independenceDay"), ("peace", "peaceDay"),
            ("meak", "meakBochea"), ("visak", "visakBochea"), ("visakha", "visakBochea"), ("plowing", "royalPloughing"),
            ("ploughing", "royalPloughing"), ("pchum", "pchumBen"), ("water festival", "waterFestival"),
        ]
        return table.first { lower.contains($0.0) }?.1
    }

    private static func khmerName(forGoogleName name: String) -> String {
        guard let key = canonicalKey(forGoogleName: name),
              let rule = fixed.first(where: { $0.rule.key == key })?.rule ?? lunar.first(where: { $0.rule.key == key })?.rule
        else { return name.localizedCaseInsensitiveContains("special") ? "ថ្ងៃឈប់សម្រាកពិសេស" : name }
        return rule.khmerName
    }

    /// The next public holidays from `day`, for the widget.
    static func upcoming(from day: CalendarDay, count: Int, google: [CalendarDay: [String]] = [:]) -> [(day: CalendarDay, holiday: KhmerHoliday)] {
        var found: [(CalendarDay, KhmerHoliday)] = []
        var cursor = day
        var steps = 0
        while found.count < count, steps < 400 {
            for holiday in holidays(on: cursor, google: google) where holiday.isPublic {
                if !found.contains(where: { $0.1.key == holiday.key && $0.0.adding(days: 3) >= cursor }) {
                    found.append((cursor, holiday))
                }
            }
            cursor = cursor.adding(days: 1)
            steps += 1
        }
        return Array(found.prefix(count))
    }
}

/// Reads the all-day events of an iCalendar (.ics) file: Google's public
/// holiday calendars come as one.
nonisolated enum ICalendarReader {
    static func allDayEvents(in text: String) -> [CalendarDay: [String]] {
        // Long lines are folded with a CRLF and a space.
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: "").replacingOccurrences(of: "\n ", with: "")
        var events: [CalendarDay: [String]] = [:]
        for block in unfolded.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
            var start: CalendarDay?
            var summary: String?
            for line in block.components(separatedBy: .newlines) {
                if line.hasPrefix("DTSTART") {
                    start = CalendarDay(compact: String(line.split(separator: ":").last?.prefix(8) ?? ""))
                } else if line.hasPrefix("SUMMARY") {
                    summary = line.split(separator: ":", maxSplits: 1).last.map {
                        String($0).replacingOccurrences(of: "\\,", with: ",").trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            if let start, let summary, !summary.isEmpty {
                events[start, default: []].append(summary)
            }
        }
        return events
    }
}
