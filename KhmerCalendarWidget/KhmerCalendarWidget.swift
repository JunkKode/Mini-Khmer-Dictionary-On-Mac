//
//  KhmerCalendarWidget.swift
//  Khmer Calendar widget
//
//  Two widgets: the month as a Khmer calendar (small, medium, large), and
//  today in both calendars with the next public holidays. Both use the shared
//  lunar calendar and holiday rules in Shared/; holidays are the calculated
//  ones, since widgets don't go online.
//

import AppKit
import SwiftUI
import WidgetKit

@main
struct KhmerCalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        KhmerMonthWidget()
        KhmerCalendarWidget()
    }
}

/// The month, Sunday first: holidays in red, observances in blue, holy days
/// with a monk, and the lunar day under each date in the large size.
///
/// It has the kind the first version of the widget used, `KhmerCalendar`, so
/// widgets already on the desktop and Xcode's Run show the month.
struct KhmerMonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KhmerCalendar", provider: Provider()) { entry in
            KhmerMonthWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Khmer Calendar")
        .description("This month with lunar days, Buddhist holy days and public holidays.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct KhmerCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KhmerDate", provider: Provider()) { entry in
            KhmerCalendarWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Khmer Date")
        .description("Today's date in the Khmer lunar and solar calendars, and the next public holidays.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DayEntry: TimelineEntry {
    let date: Date
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(DayEntry(date: Date()))
    }

    /// One entry per day for a week, each starting at midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let calendar = KhmerDateText.calendar
        let today = calendar.startOfDay(for: Date())
        let entries = (0..<7).map { DayEntry(date: calendar.date(byAdding: .day, value: $0, to: today)!) }
        completion(Timeline(entries: [DayEntry(date: Date())] + entries.dropFirst(), policy: .atEnd))
    }
}

struct KhmerCalendarWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    private var day: CalendarDay { CalendarDay(entry.date) }
    private var lunar: KhmerLunarDate? { KhmerLunarCalendar.date(for: entry.date) }
    private var holidaysToday: [KhmerHoliday] { KhmerHolidays.holidays(on: day).filter(\.isPublic) }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                today
                Divider()
                upcoming
            }
        default:
            today
        }
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(KhmerDateText.weekday(of: entry.date))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(holidaysToday.isEmpty ? Color.accentColor : .red)
            Text(KhmerDateText.digits(String(day.day)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(holidaysToday.isEmpty ? Color.primary : .red)
                .minimumScaleFactor(0.6)
            Text("ខែ\(KhmerDateText.months[day.month - 1]) \(KhmerDateText.digits(String(day.year)))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            if let lunar {
                HStack(spacing: 4) {
                    if lunar.isHolyDay {
                        Image(systemName: lunar.day == 15 && lunar.isWaxing ? "circle.fill" : "circle.lefthalf.filled")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                    Text(lunar.dayAndMonth)
                        .font(.system(size: 12, weight: .medium))
                }
                Text("ឆ្នាំ\(lunar.animalYear) \(lunar.era)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let holiday = holidaysToday.first {
                Text(holiday.khmerName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ថ្ងៃឈប់សម្រាកខាងមុខ")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(KhmerHolidays.upcoming(from: day.adding(days: 1), count: 3).enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.holiday.khmerName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text("\(KhmerDateText.weekday(of: item.day.date())) \(KhmerDateText.digits(String(item.day.day))) \(KhmerDateText.months[item.day.month - 1]) · \(daysUntil(item.day))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func daysUntil(_ target: CalendarDay) -> String {
        let days = KhmerDateText.calendar.dateComponents([.day], from: day.date(), to: target.date()).day ?? 0
        return days == 1 ? "ស្អែក" : "\(KhmerDateText.digits(String(days))) ថ្ងៃទៀត"
    }
}

// MARK: - Month

struct KhmerMonthWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    private var today: CalendarDay { CalendarDay(entry.date) }

    var body: some View {
        let days = KhmerMonth.days(year: today.year, month: today.month)
        let weeks = days.count / 7
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(KhmerDateText.months[today.month - 1])
                    .font(.system(size: family == .systemLarge ? 20 : 14, weight: .semibold))
                Spacer(minLength: 4)
                Text(KhmerMonth.englishMonth(today.month))
                    .font(.system(size: family == .systemLarge ? 20 : 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(family == .systemSmall ? KhmerMonth.tinyWeekdayNames[index] : KhmerMonth.weekdayNames[index])
                        .font(.system(size: family == .systemLarge ? 12 : 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, family == .systemLarge ? 6 : 2)
            Divider()
            VStack(spacing: 0) {
                ForEach(0..<weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(days[(week * 7)..<(week * 7 + 7)]) { square in
                            dayCell(square)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.top, 2)
        }
    }

    private func dayCell(_ square: KhmerMonthDay) -> some View {
        let isToday = square.day == today
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                if square.isHolyDay, family != .systemSmall {
                    WidgetHolyDayIcon(size: family == .systemLarge ? 13 : 10)
                }
                Text("\(square.day.day)")
                    .font(.system(size: family == .systemLarge ? 16 : 13, weight: .medium, design: .rounded))
            }
            if family == .systemLarge {
                Text(square.lunarLabel)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(color(for: square, isToday: isToday))
        .opacity(square.isInMonth ? 1 : 0.4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .padding(1)
            }
        }
    }

    private func color(for square: KhmerMonthDay, isToday: Bool) -> Color {
        switch square.tone {
        case .holiday: .red
        case .observance: .blue
        case .plain: isToday ? .accentColor : .primary
        }
    }
}

/// The Buddha on holy days: the `buddhist` image in the widget's own asset
/// catalog (a small copy of the app's), or a meditating figure without it.
struct WidgetHolyDayIcon: View {
    var size: CGFloat

    var body: some View {
        if let image = NSImage(named: "buddhist") {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(height: size * 1.25)
        } else {
            Image(systemName: "figure.mind.and.body")
                .font(.system(size: size * 0.85, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }
}

