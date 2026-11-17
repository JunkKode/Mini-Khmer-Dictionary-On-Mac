//
//  CalendarView.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// A month in both calendars, laid out like a printed Khmer calendar: the
/// solar date with its lunar day under it, holy days marked with a monk,
/// holidays in red and observances in blue, and every event of the month
/// listed underneath.
struct CalendarView: View {
    @ObservedObject var model: CalendarModel
    let onCopy: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    /// Which way the last month change went, for the slide.
    @State private var forward = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    monthTable(model.monthDays)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    selectedDayBar
                    Spacer(minLength: 0)
                }
                .frame(width: 380)

                Divider()

                eventList(model.monthEvents)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.refreshIfNeeded() }
    }

    private var springy: Animation? {
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.86)
    }

    private func changeMonth(by offset: Int) {
        forward = offset > 0
        withAnimation(springy) { model.showMonth(offset: offset) }
    }

    // MARK: - Header

    private var header: some View {
        let span = KhmerMonth.lunarSpan(year: model.month.year, month: model.month.month)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(KhmerDateText.months[model.month.month - 1])
                    .font(.system(size: 22, weight: .bold))
                Text("\(KhmerMonth.englishMonth(model.month.month)) \(String(model.month.year))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .id("title-\(model.month.year)-\(model.month.month)")
            .transition(.opacity)

            HStack(spacing: 0) {
                Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                    .help("Previous month (Page Up)")
                Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
                    .help("Next month (Page Down)")
            }
            .buttonStyle(.borderless)

            Button("Today") {
                forward = model.today > model.selected
                withAnimation(springy) { model.goToToday() }
            }
            .controlSize(.small)
            .disabled(model.selected == model.today)
            .help("Go to today (Home)")

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(span.months)
                    .font(.system(size: 13, weight: .medium))
                Text(span.year)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            syncButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var syncButton: some View {
        Button {
            Task { await model.sync() }
        } label: {
            Group {
                if model.isSyncing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: model.syncError != nil ? "exclamationmark.icloud" : model.google.isEmpty ? "icloud.and.arrow.down" : "checkmark.icloud")
                        .foregroundStyle(model.syncError != nil ? Color.orange : Color.secondary)
                }
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help(syncHelp)
    }

    private var syncHelp: String {
        if let error = model.syncError { return error }
        guard let last = model.lastSync else {
            return "Fetch Cambodia's official public holidays from Google Calendar to check the calculated ones"
        }
        return "Holidays checked against Google Calendar, synced \(last.formatted(date: .abbreviated, time: .shortened)). Click to sync now."
    }

    // MARK: - Grid

    private func monthTable(_ days: [KhmerMonthDay]) -> some View {
        let weeks = days.count / 7
        let rowHeight: CGFloat = weeks > 5 ? 50 : 58
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(KhmerMonth.weekdayNames[index])
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .overlay(alignment: .trailing) { if index < 6 { separator(vertical: true) } }
                }
            }
            .background(Color.primary.opacity(0.05))
            separator(vertical: false)

            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<weeks, id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(days[(week * 7)..<(week * 7 + 7)]) { square in
                                cell(square, height: rowHeight)
                                    .overlay(alignment: .trailing) {
                                        if square.day != days[week * 7 + 6].day { separator(vertical: true) }
                                    }
                            }
                        }
                        if week < weeks - 1 { separator(vertical: false) }
                    }
                }
                .id("grid-\(model.month.year)-\(model.month.month)")
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                ))
            }
            .clipped()
        }
        .background(Color.primary.opacity(0.025))
        .animation(springy, value: model.selected)  // arrow keys glide too
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func separator(vertical: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }

    private func cell(_ square: KhmerMonthDay, height: CGFloat) -> some View {
        let isToday = square.day == model.today
        let isSelected = square.day == model.selected
        return VStack(spacing: 0) {
            HStack(spacing: 1) {
                if square.isHolyDay {
                    HolyDayIcon(size: 12)
                }
                Text("\(square.day.day)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(color(for: square))
            }
            Text(square.lunarLabel)
                .font(.system(size: 9.5))
                .foregroundStyle(square.tone == .plain ? Color.secondary : color(for: square))
                .lineLimit(1)
            if let note = square.moonNote {
                Text(note)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .opacity(square.isInMonth ? 1 : 0.35)
        .background {
            ZStack {
                if isToday {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                        .padding(2)
                }
                if isSelected {
                    // One highlight that glides to whichever day is picked.
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                        .padding(2)
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if square.day.month != model.month.month { forward = square.day > model.selected }
            withAnimation(springy) { model.select(square.day) }
        }
        .help(square.holidays.map(\.khmerName).joined(separator: "\n"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func color(for square: KhmerMonthDay) -> Color {
        switch square.tone {
        case .holiday: .red
        case .observance: .blue
        case .plain: .primary
        }
    }

    // MARK: - Selected day

    private var selectedDayBar: some View {
        let date = model.selected.date()
        return HStack(spacing: 6) {
            Text(KhmerDateText.lunarAndSolar(date) ?? KhmerDateText.solar(date))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                onCopy(KhmerDateText.lunarAndSolar(date) ?? KhmerDateText.solar(date))
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Copy the date in both calendars")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Events

    private func eventList(_ events: [KhmerMonthDay]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("ព្រឹត្តិការណ៍")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Events in \(KhmerMonth.englishMonth(model.month.month))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if !events.isEmpty {
                            Text("\(events.reduce(0) { $0 + $1.holidays.count })")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                    .padding(.bottom, 2)
                    if events.isEmpty {
                        Text("No holidays or observances this month.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    ForEach(events) { square in
                        EventDayRow(square: square, isSelected: square.day == model.selected)
                            .id(square.day)
                            .onTapGesture { withAnimation(springy) { model.select(square.day) } }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: model.selected) { day in
                guard events.contains(where: { $0.day == day }) else { return }
                withAnimation(springy) { proxy.scrollTo(day, anchor: .top) }
            }
        }
    }
}

/// The Buddha on Buddhist holy days (ថ្ងៃសីល), from the `buddhist` image in
/// Assets.xcassets, or a meditating figure if the image is missing.
struct HolyDayIcon: View {
    var size: CGFloat = 12

    var body: some View {
        if let image = NSImage(named: "buddhist") {
            // Taller than wide: keep its shape at the text's height.
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: size * 1.25)
        } else {
            Image(systemName: "figure.mind.and.body")
                .font(.system(size: size * 0.9, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }
}

/// A day with its events, as in the list under a printed calendar: the
/// weekday and date on the left, a card per event on the right.
private struct EventDayRow: View {
    let square: KhmerMonthDay
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Text(KhmerMonth.weekdayNames[KhmerDateText.calendar.component(.weekday, from: square.day.date()) - 1])
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(square.day.day)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(square.holidays.enumerated()), id: \.offset) { _, holiday in
                    EventCard(holiday: holiday, isSelected: isSelected)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

private struct EventCard: View {
    let holiday: KhmerHoliday
    let isSelected: Bool

    private var color: Color { holiday.isPublic ? .red : .blue }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // The Khmer name already says which day: (ថ្ងៃទី១).
                Text("\(holiday.khmerName) (\(holiday.name.replacingOccurrences(of: #" \(Day \d\)"#, with: "", options: .regularExpression)))")
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = holiday.note {
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 4)
            sourceBadge
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12))
        )
    }

    private var sourceBadge: some View {
        let (icon, color, help): (String, Color, String) = switch holiday.source {
        case .both: ("checkmark.seal.fill", .green, "The Khmer calendar and Google's official list agree on this day")
        case .google: ("globe", .blue, "Only in Google's official list, e.g. a special day off")
        case .calculated: ("function", .secondary, "Worked out from the Khmer calendar and the law")
        }
        return Image(systemName: icon)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .help(help)
    }
}
