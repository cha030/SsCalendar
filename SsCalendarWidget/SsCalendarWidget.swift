import SwiftUI
import WidgetKit

struct SsCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CalendarWidgetConstants.kind,
            provider: CalendarWidgetProvider()
        ) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("월간 캘린더")
        .description("이번 달 날짜와 저장된 일정을 한눈에 확인합니다.")
        .supportedFamilies([
            .systemMedium,
            .systemLarge,
            .systemExtraLargePortrait
        ])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.previewEntry
}

#Preview(as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.previewEntry
}

#Preview("4주 Large", as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.emptyEntry(
        for: CalendarWidgetCalendar.korean.date(
            from: DateComponents(year: 2026, month: 2, day: 1)
        ) ?? .now
    )
}

#Preview("6주 Large", as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.emptyEntry(
        for: CalendarWidgetCalendar.korean.date(
            from: DateComponents(year: 2026, month: 8, day: 1)
        ) ?? .now
    )
}

#Preview("Extra Large Portrait", as: .systemExtraLargePortrait) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.previewEntry
}

#Preview("4주 Extra Large Portrait", as: .systemExtraLargePortrait) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.emptyEntry(
        for: CalendarWidgetCalendar.korean.date(
            from: DateComponents(year: 2026, month: 2, day: 1)
        ) ?? .now
    )
}

#Preview("6주 Extra Large Portrait", as: .systemExtraLargePortrait) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.emptyEntry(
        for: CalendarWidgetCalendar.korean.date(
            from: DateComponents(year: 2026, month: 8, day: 1)
        ) ?? .now
    )
}

/// 위젯 글자 크기 단계 확인용: 6주 달 + 일정이 많은 날(= 오늘) + 공휴일이 있는 날을 함께 보여준다.
/// CalendarWidgetView.swift의 단계 3 미리보기에서도 재사용하므로 private로 두지 않는다.
func calendarTextSizePreviewEntry(level: Int) -> CalendarWidgetEntry {
    CalendarTextSizeSetting.store.set(level, forKey: CalendarTextSizeSetting.storageKey)

    let calendar = CalendarWidgetCalendar.korean
    let grid = CalendarWidgetCalendar.monthGrid(
        containing: calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)) ?? .now
    )
    let busyDay = calendar.date(bySetting: .day, value: 10, of: grid.monthStart) ?? grid.monthStart
    let holidayDay = calendar.date(bySetting: .day, value: 15, of: grid.monthStart) ?? grid.monthStart
    let multiDayStart = calendar.date(bySetting: .day, value: 8, of: grid.monthStart) ?? grid.monthStart
    let multiDayEnd = calendar.date(byAdding: .day, value: 4, to: multiDayStart) ?? multiDayStart

    let occurrences = [
        CalendarWidgetOccurrence(id: "busy-1", title: "아침 운동", colorName: "파란색", firstDay: busyDay, lastDay: busyDay),
        CalendarWidgetOccurrence(id: "busy-2", title: "팀 회의", colorName: "초록색", firstDay: busyDay, lastDay: busyDay),
        CalendarWidgetOccurrence(id: "busy-3", title: "점심 약속", colorName: "보라색", firstDay: busyDay, lastDay: busyDay),
        CalendarWidgetOccurrence(id: "busy-4", title: "병원 진료", colorName: "빨간색", firstDay: busyDay, lastDay: busyDay),
        CalendarWidgetOccurrence(
            id: "multi-1",
            title: "여름 휴가",
            colorName: "초록색",
            firstDay: multiDayStart,
            lastDay: multiDayEnd
        )
    ]

    let days = grid.dates.map { day -> CalendarWidgetDay in
        let dayEvents: [CalendarWidgetEvent] = occurrences.compactMap { occurrence in
            guard occurrence.firstDay <= day, day <= occurrence.lastDay else { return nil }
            return CalendarWidgetEvent(id: occurrence.id, title: occurrence.title, colorName: occurrence.colorName)
        }
        let isHoliday = calendar.isDate(day, inSameDayAs: holidayDay)

        let components = CalendarWidgetCalendar.components(for: day, calendar: calendar)
        return CalendarWidgetDay(
            date: day,
            dateString: CalendarWidgetCalendar.dateString(for: day, calendar: calendar),
            year: components.year,
            month: components.month,
            dayNumber: components.day,
            weekday: components.weekday,
            isCurrentMonth: calendar.isDate(day, equalTo: grid.monthStart, toGranularity: .month),
            isToday: calendar.isDate(day, inSameDayAs: busyDay),
            isHoliday: isHoliday,
            holidayTitle: isHoliday ? "광복절" : nil,
            importantMarker: calendar.isDate(day, inSameDayAs: busyDay) ? .sun : .none,
            events: dayEvents
        )
    }

    return CalendarWidgetEntry(
        date: Date(),
        monthStart: grid.monthStart,
        monthDateString: CalendarWidgetCalendar.dateString(for: grid.monthStart, calendar: calendar),
        monthYear: CalendarWidgetCalendar.components(for: grid.monthStart, calendar: calendar).year,
        monthNumber: CalendarWidgetCalendar.components(for: grid.monthStart, calendar: calendar).month,
        selectedDate: busyDay,
        selectedDateString: CalendarWidgetCalendar.dateString(for: busyDay, calendar: calendar),
        todayDayNumber: CalendarWidgetCalendar.components(for: Date(), calendar: calendar).day,
        days: days,
        occurrences: occurrences
    )
}

#Preview("단계 0 보통 - 6주 Large", as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    calendarTextSizePreviewEntry(level: 0)
}

#Preview("단계 1 크게 - 6주 Large", as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    calendarTextSizePreviewEntry(level: 1)
}

#Preview("단계 2 더 크게 - 6주 Large", as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    calendarTextSizePreviewEntry(level: 2)
}

#Preview("단계 2 더 크게 - Extra Large Portrait", as: .systemExtraLargePortrait) {
    SsCalendarWidget()
} timeline: {
    calendarTextSizePreviewEntry(level: 2)
}

