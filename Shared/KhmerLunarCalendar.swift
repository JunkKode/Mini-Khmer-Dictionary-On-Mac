//
//  KhmerLunarCalendar.swift
//  Mini Khmer Dictionary
//
//  Shared by the app and the Khmer Calendar widget. Foundation only; tested
//  by Tools/test_formula_engine.sh.
//

import Foundation

/// A day in the Khmer lunar calendar (ចន្ទគតិ): ថ្ងៃ១៥កើត ខែពិសាខ.
nonisolated struct KhmerLunarDate: Hashable, Sendable {
    /// 1–15.
    let day: Int
    /// កើត, the waxing half, or រោច, the waning half.
    let isWaxing: Bool
    let month: KhmerLunarCalendar.Month
    /// ព.ស., the Buddhist era. It moves on the day after Visakha Bochea.
    let buddhistEraYear: Int
    /// ជូត … កុរ. Moves at Khmer New Year in April.
    let animalYear: String
    /// ឯកស័ក … សំរឹទ្ធិស័ក, the ten-year cycle. Moves at Khmer New Year.
    let era: String

    /// ថ្ងៃ១៥កើត ខែពិសាខ
    var dayAndMonth: String {
        "\(KhmerDateText.digits(String(day)))\(isWaxing ? "កើត" : "រោច") ខែ\(month.name)"
    }

    /// ១៥កើត ខែពិសាខ ឆ្នាំរោង ឆស័ក ព.ស. ២៥៦៨
    var fullText: String {
        "\(dayAndMonth) ឆ្នាំ\(animalYear) \(era) ព.ស. \(KhmerDateText.digits(String(buddhistEraYear)))"
    }

    /// Buddhist holy days (ថ្ងៃសីល): the 8th and 15th of each half, and the
    /// 14th of a short (29-day) month's waning half.
    var isHolyDay: Bool {
        day == 8 || day == 15 || (!isWaxing && day == 14 && month.days(leapDayYear: false) == 29)
    }
}

/// Converts Gregorian dates to the Khmer lunar calendar.
///
/// This is the traditional calculation (from *Pratitin Soryakkatik-
/// Chankatik 1900–1999*, as implemented by the open-source momentkh): a
/// lunar year has 354 days, 355 when ជេស្ឋ gets a leap day, or 384 when
/// អាសាឍ is doubled into បឋមាសាឍ and ទុតិយាសាឍ. Which kind a year is follows
/// from its អាហារគុណ, បូតិថី and អវមាន.
nonisolated enum KhmerLunarCalendar {
    enum Month: Int, CaseIterable, Sendable {
        case migasir, boss, meak, phalkun, cheit, pisak, jesth, asadh, srap, phatrabot, assoch, kadeuk
        case pathamasadh, tutiyasadh

        var name: String {
            ["មិគសិរ", "បុស្ស", "មាឃ", "ផល្គុន", "ចេត្រ", "ពិសាខ", "ជេស្ឋ", "អាសាឍ", "ស្រាពណ៍", "ភទ្របទ", "អស្សុជ", "កត្ដិក", "បឋមាសាឍ", "ទុតិយាសាឍ"][rawValue]
        }

        func days(leapDayYear: Bool) -> Int {
            switch self {
            case .jesth where leapDayYear: 30
            case .pathamasadh, .tutiyasadh: 30
            default: rawValue % 2 == 0 ? 29 : 30
            }
        }
    }

    static let animals = ["ជូត", "ឆ្លូវ", "ខាល", "ថោះ", "រោង", "ម្សាញ់", "មមី", "មមែ", "វក", "រកា", "ច", "កុរ"]
    static let eras = ["សំរឹទ្ធិស័ក", "ឯកស័ក", "ទោស័ក", "ត្រីស័ក", "ចត្វាស័ក", "បញ្ចស័ក", "ឆស័ក", "សប្តស័ក", "អដ្ឋស័ក", "នព្វស័ក"]

    // MARK: - Year arithmetic

    private static func aharkun(_ be: Int) -> Int { (be * 292_207 + 499) / 800 + 4 }
    private static func kromthupul(_ be: Int) -> Int { 800 - (be * 292_207 + 499) % 800 }
    private static func isSolarLeap(_ be: Int) -> Bool { kromthupul(be) <= 207 }
    private static func avoman(_ be: Int) -> Int { (aharkun(be) * 11 + 25) % 692 }

    private static func bodithey(_ be: Int) -> Int {
        let ahk = aharkun(be)
        return ((11 * ahk + 25) / 692 + ahk + 29) % 30
    }

    /// 0 regular, 1 leap month, 2 leap day, 3 both (resolved by `protetinLeap`).
    private static func boditheyLeap(_ be: Int) -> Int {
        let avoman = Self.avoman(be)
        let bodithey = Self.bodithey(be)
        var monthLeap = bodithey >= 25 || bodithey <= 5
        var dayLeap = false
        if isSolarLeap(be) {
            dayLeap = avoman <= 126
        } else if avoman <= 137 {
            // 137 followed by 0 must be a normal year.
            dayLeap = Self.avoman(be + 1) != 0
        }
        // 25 then 5: only the 5 is a leap-month year. 24 then 6: the 24 is.
        if bodithey == 25, Self.bodithey(be + 1) == 5 { monthLeap = false }
        if bodithey == 24, Self.bodithey(be + 1) == 6 { monthLeap = true }
        switch (monthLeap, dayLeap) {
        case (true, true): return 3
        case (true, false): return 1
        case (false, true): return 2
        default: return 0
        }
    }

    /// 0 regular, 1 leap month (384 days), 2 leap day (355 days).
    private static func protetinLeap(_ be: Int) -> Int {
        let leap = boditheyLeap(be)
        if leap == 3 { return 1 }
        if leap == 1 || leap == 2 { return leap }
        return boditheyLeap(be - 1) == 3 ? 2 : 0
    }

    private static func daysInYear(_ be: Int) -> Int {
        switch protetinLeap(be) {
        case 1: 384
        case 2: 355
        default: 354
        }
    }

    private static func daysInMonth(_ month: Month, _ be: Int) -> Int {
        month.days(leapDayYear: protetinLeap(be) == 2)
    }

    private static func month(after month: Month, _ be: Int) -> Month {
        switch month {
        case .jesth: protetinLeap(be) == 1 ? .pathamasadh : .asadh
        case .kadeuk: .migasir
        case .pathamasadh: .tutiyasadh
        case .tutiyasadh: .srap
        default: Month(rawValue: month.rawValue + 1)!
        }
    }

    // MARK: - Days

    /// Days since 1900-01-01 for a Gregorian date, by its calendar fields,
    /// so time zones and daylight saving never shift the day.
    private static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        // Days from civil (Howard Hinnant), relative to 1900-01-01.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468 + 25_567
    }

    private static func civil(_ number: Int) -> (year: Int, month: Int, day: Int) {
        let z = number - 25_567 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// The BE year used while counting: the Gregorian year + 543 through
    /// April, + 544 from May.
    private static func countingYear(_ number: Int) -> Int {
        let date = civil(number)
        return date.year + (date.month <= 4 ? 543 : 544)
    }

    /// Supported range: the counting walks year by year from 1900.
    static let supportedYears = 1900...2200

    /// The lunar day for a Gregorian year, month and day, or `nil` outside
    /// `supportedYears`.
    static func lunarDay(year: Int, month: Int, day: Int) -> (day: Int, month: Month)? {
        guard supportedYears.contains(year) else { return nil }
        let target = dayNumber(year: year, month: month, day: day)
        if let known = memo.lock.withLock({ memo.lunarDays[target] }) { return known }
        let result = computeLunarDay(target)
        memo.lock.withLock { memo.lunarDays[target] = result }
        return result
    }

    private static func computeLunarDay(_ target: Int) -> (day: Int, month: Month) {

        // 1900-01-01 was ១កើត ខែបុស្ស.
        var epoch = 0
        var lunarMonth = Month.boss

        // Whole lunar years first…
        while true {
            let next = civil(epoch)
            let length = daysInYear(countingYear(dayNumber(year: next.year + 1, month: next.month, day: next.day)))
            guard target - epoch > length else { break }
            epoch += length
        }
        // …then whole months.
        while target - epoch > daysInMonth(lunarMonth, countingYear(epoch)) {
            epoch += daysInMonth(lunarMonth, countingYear(epoch))
            lunarMonth = Self.month(after: lunarMonth, countingYear(epoch))
        }
        var lunarDay = target - epoch
        let length = daysInMonth(lunarMonth, countingYear(target))
        if lunarDay >= length {
            lunarDay %= length
            lunarMonth = Self.month(after: lunarMonth, countingYear(epoch))
        }
        return (lunarDay, lunarMonth)
    }

    /// The Gregorian day of Visakha Bochea (១៥កើត ខែពិសាខ) in `year`.
    static func visakhaBochea(year: Int) -> (month: Int, day: Int)? {
        if let known = memo.lock.withLock({ memo.visakha[year] }) { return known }
        let found = findVisakhaBochea(year: year)
        memo.lock.withLock { memo.visakha[year] = .some(found) }
        return found
    }

    private static func findVisakhaBochea(year: Int) -> (month: Int, day: Int)? {
        var number = dayNumber(year: year, month: 1, day: 1)
        for _ in 0..<366 {
            let date = civil(number)
            if let lunar = lunarDay(year: date.year, month: date.month, day: date.day),
               lunar.month == .pisak, lunar.day == 14 {
                return (date.month, date.day)
            }
            number += 1
        }
        return nil
    }

    /// The full lunar date for a Gregorian date.
    ///
    /// The animal year and era are taken to turn at Khmer New Year on
    /// 14 April; the exact hour of ទេវតាចុះ varies by a day from year to year,
    /// so on 13–14 April they may be a day early or late.
    static func date(year: Int, month: Int, day: Int) -> KhmerLunarDate? {
        let key = dayNumber(year: year, month: month, day: day)
        if let known = memo.lock.withLock({ memo.dates[key] }) { return known }
        let result = computeDate(year: year, month: month, day: day)
        memo.lock.withLock { memo.dates[key] = result }
        return result
    }

    /// Answers already worked out. Every calendar square, the widget and
    /// the formulas ask for the same days again and again, and finding a
    /// year's Visak Bochea means walking its days.
    private final class Memo: @unchecked Sendable {
        let lock = NSLock()
        var lunarDays: [Int: (day: Int, month: Month)] = [:]
        var dates: [Int: KhmerLunarDate?] = [:]
        var visakha: [Int: (month: Int, day: Int)?] = [:]
    }

    private static let memo = Memo()

    private static func computeDate(year: Int, month: Int, day: Int) -> KhmerLunarDate? {
        guard let lunar = lunarDay(year: year, month: month, day: day) else { return nil }

        let target = dayNumber(year: year, month: month, day: day)
        var be = year + 543
        if let visakha = visakhaBochea(year: year), target > dayNumber(year: year, month: visakha.month, day: visakha.day) {
            be = year + 544
        }
        let afterNewYear = (month, day) >= (4, 14)
        let animal = animals[((year - (afterNewYear ? 4 : 5)) % 12 + 12) % 12]
        let jolak = year + (afterNewYear ? 544 : 543) - 1182
        let era = eras[(jolak % 10 + 10) % 10]

        return KhmerLunarDate(
            day: lunar.day < 15 ? lunar.day + 1 : lunar.day - 14,
            isWaxing: lunar.day < 15,
            month: lunar.month,
            buddhistEraYear: be,
            animalYear: animal,
            era: era
        )
    }

    static func date(for date: Date, calendar: Calendar = KhmerDateText.calendar) -> KhmerLunarDate? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return self.date(year: parts.year!, month: parts.month!, day: parts.day!)
    }
}

/// Dates written out in Khmer, for the app and the widget.
nonisolated enum KhmerDateText {
    /// One Gregorian calendar for everything, following the Mac's time zone.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    static let weekdays = ["ថ្ងៃអាទិត្យ", "ថ្ងៃច័ន្ទ", "ថ្ងៃអង្គារ", "ថ្ងៃពុធ", "ថ្ងៃព្រហស្បតិ៍", "ថ្ងៃសុក្រ", "ថ្ងៃសៅរ៍"]
    /// អា ច អ ពុ ព្រ សុ ស, for calendar column heads.
    static let shortWeekdays = ["អា", "ច", "អ", "ពុ", "ព្រ", "សុ", "ស"]
    static let months = ["មករា", "កុម្ភៈ", "មីនា", "មេសា", "ឧសភា", "មិថុនា", "កក្កដា", "សីហា", "កញ្ញា", "តុលា", "វិច្ឆិកា", "ធ្នូ"]

    /// ១២៣ for 123.
    static func digits(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            ("0"..."9").contains(scalar) ? Unicode.Scalar(scalar.value - 0x30 + 0x17E0)! : scalar
        }))
    }

    /// ថ្ងៃច័ន្ទ for a Monday.
    static func weekday(of date: Date) -> String {
        weekdays[calendar.component(.weekday, from: date) - 1]
    }

    /// ថ្ងៃអាទិត្យ ទី១៥ ខែវិច្ឆិកា ឆ្នាំ២០២៦
    static func solar(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(weekday(of: date)) ទី\(digits(String(parts.day!))) ខែ\(months[parts.month! - 1]) ឆ្នាំ\(digits(String(parts.year!)))"
    }

    /// Both calendars in the traditional form: ថ្ងៃ ៦កើត ខែកត្ដិក ឆ្នាំមមី
    /// អដ្ឋស័ក ព.ស. ២៥៧០ ត្រូវនឹង ថ្ងៃអាទិត្យ ទី១៥ ខែវិច្ឆិកា ឆ្នាំ២០២៦.
    static func lunarAndSolar(_ date: Date) -> String? {
        guard let lunar = KhmerLunarCalendar.date(for: date, calendar: calendar) else { return nil }
        return "ថ្ងៃ \(lunar.fullText) ត្រូវនឹង \(solar(date))"
    }
}
