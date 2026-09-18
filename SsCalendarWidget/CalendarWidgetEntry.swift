import Foundation
import WidgetKit

struct CalendarWidgetEvent: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let colorName: String
}

struct CalendarWidgetOccurrence: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let colorName: String
    let firstDay: Date
    let lastDay: Date

    var isMultiDay: Bool { firstDay != lastDay }
}

struct CalendarWidgetDay: Identifiable, Hashable, Sendable {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isHoliday: Bool
    let holidayTitle: String?
    let events: [CalendarWidgetEvent]

    var id: Date { date }
}

struct CalendarWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let monthStart: Date
    let selectedDate: Date?
    let days: [CalendarWidgetDay]
    let occurrences: [CalendarWidgetOccurrence]
}

enum CalendarWidgetCalendar {
    static var korean: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    static func monthGrid(containing date: Date) -> (monthStart: Date, interval: DateInterval, dates: [Date]) {
        let calendar = korean
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: date),
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start),
            let lastVisibleDate = calendar.date(byAdding: .second, value: -1, to: monthInterval.end),
            let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastVisibleDate)
        else {
            let day = calendar.startOfDay(for: date)
            return (day, DateInterval(start: day, duration: 86_400), [day])
        }

        let interval = DateInterval(start: firstWeek.start, end: lastWeek.end)
        var dates: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return (monthInterval.start, interval, dates)
    }

    static func emptyEntry(for date: Date) -> CalendarWidgetEntry {
        let grid = monthGrid(containing: date)
        let calendar = korean
        let days = grid.dates.map { day in
            CalendarWidgetDay(
                date: day,
                isCurrentMonth: calendar.isDate(day, equalTo: grid.monthStart, toGranularity: .month),
                isToday: calendar.isDateInToday(day),
                isHoliday: false,
                holidayTitle: nil,
                events: []
            )
        }
        return CalendarWidgetEntry(
            date: date,
            monthStart: grid.monthStart,
            selectedDate: nil,
            days: days,
            occurrences: []
        )
    }

    static var previewEntry: CalendarWidgetEntry {
        let calendar = korean
        let now = Date()
        let grid = monthGrid(containing: now)
        let today = calendar.startOfDay(for: now)
        let holidayDate = calendar.date(
            bySetting: .day,
            value: 25,
            of: grid.monthStart
        )
        let sampleDates = [
            today,
            calendar.date(byAdding: .day, value: 1, to: today),
            calendar.date(byAdding: .day, value: 3, to: today)
        ].compactMap { $0 }
        let previewOccurrences = [
            CalendarWidgetOccurrence(
                id: "preview-single-1",
                title: "친구 만나기",
                colorName: "초록색",
                firstDay: today,
                lastDay: today
            ),
            CalendarWidgetOccurrence(
                id: "preview-single-2",
                title: "프로젝트 회의",
                colorName: "파란색",
                firstDay: today,
                lastDay: today
            ),
            CalendarWidgetOccurrence(
                id: "preview-multi-1",
                title: "여행",
                colorName: "보라색",
                firstDay: sampleDates[1],
                lastDay: calendar.date(byAdding: .day, value: 4, to: today) ?? sampleDates[1]
            ),
            CalendarWidgetOccurrence(
                id: "preview-multi-2",
                title: "출장",
                colorName: "빨간색",
                firstDay: sampleDates[2],
                lastDay: calendar.date(byAdding: .day, value: 14, to: today) ?? sampleDates[2]
            )
        ]

        let days = grid.dates.map { day in
            let sampleEvents: [CalendarWidgetEvent] = previewOccurrences.compactMap { occurrence in
                guard occurrence.firstDay <= day, day <= occurrence.lastDay else {
                    return nil
                }
                return CalendarWidgetEvent(
                    id: occurrence.id,
                    title: occurrence.title,
                    colorName: occurrence.colorName
                )
            }

            return CalendarWidgetDay(
                date: day,
                isCurrentMonth: calendar.isDate(day, equalTo: grid.monthStart, toGranularity: .month),
                isToday: calendar.isDateInToday(day),
                isHoliday: holidayDate.map { calendar.isDate(day, inSameDayAs: $0) } ?? false,
                holidayTitle: holidayDate.map { calendar.isDate(day, inSameDayAs: $0) } == true ? "추석" : nil,
                events: sampleEvents
            )
        }
        return CalendarWidgetEntry(
            date: now,
            monthStart: grid.monthStart,
            selectedDate: today,
            days: days,
            occurrences: previewOccurrences
        )
    }
}
