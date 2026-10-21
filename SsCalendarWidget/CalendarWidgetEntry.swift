import CoreGraphics
import Foundation
import WidgetKit

/// 시스템 캘린더 색상(sRGB, 0...1). 로컬 일정은 사용하지 않고 기존 colorName을 쓴다.
/// 생성 시 값을 검증하므로, 잘못된 색상은 nil이 되어 colorName 기반 기본 색으로 표시된다.
struct CalendarWidgetSystemColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init?(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        let components = [red, green, blue, opacity]
        guard components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return nil
        }

        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// EKCalendar.cgColor 등 임의 색 공간의 CGColor를 sRGB로 변환한다. 변환할 수 없으면 nil.
    init?(cgColor: CGColor?) {
        guard
            let cgColor,
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil),
            let components = converted.components,
            components.count >= 4
        else {
            return nil
        }

        self.init(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2]),
            opacity: Double(components[3])
        )
    }
}

struct CalendarWidgetEvent: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let colorName: String
    /// 시스템 캘린더 일정일 때만 설정한다. nil이면 colorName으로 색을 정한다.
    var systemColor: CalendarWidgetSystemColor? = nil
}

struct CalendarWidgetOccurrence: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let colorName: String
    let firstDay: Date
    let lastDay: Date
    /// 시스템 캘린더 일정일 때만 설정한다. nil이면 colorName으로 색을 정한다.
    var systemColor: CalendarWidgetSystemColor? = nil

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
                title: String(localized: "친구 만나기"),
                colorName: "초록색",
                firstDay: today,
                lastDay: today
            ),
            CalendarWidgetOccurrence(
                id: "preview-single-2",
                title: String(localized: "프로젝트 회의"),
                colorName: "파란색",
                firstDay: today,
                lastDay: today
            ),
            CalendarWidgetOccurrence(
                id: "preview-multi-1",
                title: String(localized: "여행"),
                colorName: "보라색",
                firstDay: sampleDates[1],
                lastDay: calendar.date(byAdding: .day, value: 4, to: today) ?? sampleDates[1]
            ),
            CalendarWidgetOccurrence(
                id: "preview-multi-2",
                title: String(localized: "출장"),
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
                holidayTitle: holidayDate.map { calendar.isDate(day, inSameDayAs: $0) } == true ? String(localized: "추석") : nil,
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
