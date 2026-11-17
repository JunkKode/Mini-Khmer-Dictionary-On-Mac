//
//  KhmerMonth.swift
//  Mini Khmer Dictionary
//
//  One month laid out for a calendar grid, shared by the Calendar tab and the
//  widget so both mark days the same way. Foundation only; tested by
//  Tools/test_formula_engine.sh.
//

import Foundation

/// One square of the month grid.
nonisolated struct KhmerMonthDay: Hashable, Identifiable, Sendable {
    let day: CalendarDay
    let isInMonth: Bool
    let lunar: KhmerLunarDate?
    let holidays: [KhmerHoliday]

    var id: CalendarDay { day }

    /// Red for a day off, blue for an observance, plain otherwise.
    enum Tone: Sendable { case plain, holiday, observance }

    var tone: Tone {
        if holidays.contains(where: \.isPublic) { return .holiday }
        if !holidays.isEmpty { return .observance }
        return .plain
    }

    /// A Buddhist holy day (ថ្ងៃសីល): the 8th and the full and new moon.
    var isHolyDay: Bool { lunar?.isHolyDay ?? false }

    /// The lunar day under the date: ៦ រោច, or the month's name on its
    /// first day.
    var lunarLabel: String {
        guard let lunar else { return "" }
        if lunar.isWaxing && lunar.day == 1 { return lunar.month.name }
        return "\(KhmerDateText.digits(String(lunar.day))) \(lunar.isWaxing ? "កើត" : "រោច")"
    }

    /// ថ្ងៃកោរ the day before a full or new moon, when monks shave, and
    /// ពេញបូណ៌មី on the full moon.
    var moonNote: String?

    var isFullMoon: Bool { lunar.map { $0.isWaxing && $0.day == 15 } ?? false }
}

nonisolated enum KhmerMonth {
    /// អាទិ ចន្ទ អង្គ ពុធ ព្រហ សុក្រ សៅរ៍
    static let weekdayNames = ["អាទិ", "ចន្ទ", "អង្គ", "ពុធ", "ព្រហ", "សុក្រ", "សៅរ៍"]
    /// For the smallest widget.
    static let tinyWeekdayNames = ["អា", "ចន្ទ", "អង្គ", "ពុ", "ព្រ", "សុ", "សៅ"]

    /// The weeks of `month`, Sunday first, padded with the days around it to
    /// whole weeks: five rows for most months, six or four for some.
    static func days(year: Int, month: Int, google: [CalendarDay: [String]] = [:]) -> [KhmerMonthDay] {
        let calendar = KhmerDateText.calendar
        let first = CalendarDay(year: year, month: month, day: 1)
        let leading = calendar.component(.weekday, from: first.date()) - 1
        let length = calendar.range(of: .day, in: .month, for: first.date())?.count ?? 30
        let weeks = Int((Double(leading + length) / 7).rounded(.up))
        let start = first.adding(days: -leading)

        let plain = (0..<(weeks * 7)).map { start.adding(days: $0) }
        let lunar = plain.map { KhmerLunarCalendar.date(for: $0.date()) }
        // One more day either side, to tell a shaving day from the next day.
        let after = KhmerLunarCalendar.date(for: plain.last!.adding(days: 1).date())

        return plain.indices.map { index in
            let day = plain[index]
            let today = lunar[index]
            let tomorrow = index + 1 < lunar.count ? lunar[index + 1] : after
            var square = KhmerMonthDay(
                day: day,
                isInMonth: day.month == month,
                lunar: today,
                holidays: KhmerHolidays.holidays(on: day, google: google)
            )
            square.moonNote = moonNote(today: today, tomorrow: tomorrow)
            return square
        }
    }

    private static func moonNote(today: KhmerLunarDate?, tomorrow: KhmerLunarDate?) -> String? {
        guard let today else { return nil }
        if today.isWaxing && today.day == 15 { return "ពេញបូណ៌មី" }
        if let tomorrow, tomorrow.isHolyDay, tomorrow.day != 8 { return "ថ្ងៃកោរ" }
        return nil
    }

    /// អស្សុជ - កត្ដិក ឆ្នាំមមី, the lunar months a solar month spans.
    static func lunarSpan(year: Int, month: Int) -> (months: String, year: String) {
        let calendar = KhmerDateText.calendar
        let first = CalendarDay(year: year, month: month, day: 1)
        let length = calendar.range(of: .day, in: .month, for: first.date())?.count ?? 30
        guard let start = KhmerLunarCalendar.date(for: first.date()),
              let end = KhmerLunarCalendar.date(for: CalendarDay(year: year, month: month, day: length).date()) else {
            return ("", "")
        }
        let months = start.month == end.month ? start.month.name : "\(start.month.name) - \(end.month.name)"
        return ("\(months) ឆ្នាំ\(end.animalYear)", "ព.ស. \(KhmerDateText.digits(String(end.buddhistEraYear)))")
    }

    /// November, in English.
    static func englishMonth(_ month: Int) -> String {
        englishMonths[month - 1]
    }

    private static let englishMonths = ["January", "February", "March", "April", "May", "June", "July",
                                        "August", "September", "October", "November", "December"]

    /// Every holiday and observance in the month, by day, for the list under
    /// the grid.
    static func events(in days: [KhmerMonthDay]) -> [KhmerMonthDay] {
        days.filter { $0.isInMonth && !$0.holidays.isEmpty }
    }
}
