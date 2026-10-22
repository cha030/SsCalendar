import SwiftData
import WidgetKit

struct CalendarWidgetProvider: TimelineProvider {
    /// 시스템 캘린더 연동이 켜져 있을 때 요청하는 다음 갱신 간격.
    /// 실제 갱신 시점은 iOS가 위젯 예산과 사용 패턴에 따라 결정하므로 늦어질 수 있다.
    private static let systemCalendarRefreshInterval: TimeInterval = 60 * 60

    func placeholder(in context: Context) -> CalendarWidgetEntry {
        CalendarWidgetCalendar.previewEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarWidgetEntry) -> Void) {
        if context.isPreview {
            completion(CalendarWidgetCalendar.previewEntry)
            return
        }

        Task { @MainActor in
            completion(loadEntry(for: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarWidgetEntry>) -> Void) {
        Task { @MainActor in
            let now = Date()
            let entry = loadEntry(for: now)
            let nextMidnight = CalendarWidgetCalendar.nextMidnight(after: now)
            completion(Timeline(entries: [entry], policy: .after(nextRefreshDate(now: now, nextMidnight: nextMidnight))))
        }
    }

    /// 연동 OFF(또는 권한 없음)면 기존처럼 자정에만 갱신을 요청한다.
    /// 연동 ON이면 앱 밖에서 바뀐 시스템 일정을 반영할 기회를 주기 위해 더 이른 갱신을 요청한다.
    @MainActor
    private func nextRefreshDate(now: Date, nextMidnight: Date) -> Date {
        guard
            let defaults = SystemCalendarQuery.sharedDefaults(),
            SystemCalendarQuery.isEnabled(in: defaults),
            SystemCalendarQuery.hasFullAccess
        else {
            return nextMidnight
        }

        return min(nextMidnight, now.addingTimeInterval(Self.systemCalendarRefreshInterval))
    }

    @MainActor
    private func loadEntry(for date: Date) -> CalendarWidgetEntry {
        let displayedMonth = WidgetMonthState.displayedMonthStart(now: date)
        let grid = CalendarWidgetCalendar.monthGrid(containing: displayedMonth)
        let calendar = DeviceCalendar.current
        let selectedDate = WidgetMonthState.selectedDate()
            ?? (calendar.isDate(displayedMonth, equalTo: date, toGranularity: .month)
                ? calendar.startOfDay(for: date)
                : nil)

        do {
            let container = try WidgetDataStore.makeModelContainer()
            let context = ModelContext(container)
            let events = try context.fetch(FetchDescriptor<Event>())
            let occurrences = EventOccurrenceService.occurrences(
                for: events,
                intersecting: grid.interval,
                calendar: calendar
            )
            let localItems = occurrences.map {
                CalendarWidgetItem(local: $0, calendar: calendar)
            }
            let items = CalendarWidgetItem.merged(
                local: localItems,
                system: systemItems(in: grid.interval, calendar: calendar)
            )
            let holidayRecords = holidayRecords(
                for: HolidayCountry.selected(in: HolidayCountry.settingsStore),
                in: grid
            )
            let holidaysByDate = Dictionary(grouping: holidayRecords) {
                "\($0.year)-\($0.month)-\($0.day)"
            }
            let widgetOccurrences = items.map(\.widgetOccurrence)

            let days = grid.dates.map { day in
                let components = calendar.dateComponents([.year, .month, .day], from: day)
                let dayKey = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
                let holidays = (holidaysByDate[dayKey] ?? [])
                    .filter(\.isHoliday)
                let dayEvents = items
                    .filter { $0.occurs(day, calendar) }
                    .map(\.widgetEvent)

                return CalendarWidgetDay(
                    date: day,
                    isCurrentMonth: calendar.isDate(day, equalTo: grid.monthStart, toGranularity: .month),
                    isToday: calendar.isDateInToday(day),
                    isHoliday: !holidays.isEmpty,
                    holidayTitle: HolidayDisplayFormatter.title(
                        for: holidays.map(\.name),
                        on: day,
                        calendar: calendar
                    ),
                    events: dayEvents
                )
            }
            return CalendarWidgetEntry(
                date: date,
                monthStart: grid.monthStart,
                selectedDate: selectedDate,
                days: days,
                occurrences: widgetOccurrences
            )
        } catch {
            return CalendarWidgetCalendar.emptyEntry(for: displayedMonth)
        }
    }

    /// 앱과 동일한 규칙(연동 ON, Full Access, 숨긴 캘린더 제외)으로 시스템 일정을 읽는다.
    /// 조건을 만족하지 않거나 App Group을 읽을 수 없으면 빈 배열이며, 로컬 일정 표시에는 영향이 없다.
    @MainActor
    private func systemItems(in interval: DateInterval, calendar: Calendar) -> [CalendarWidgetItem] {
        guard let defaults = SystemCalendarQuery.sharedDefaults() else { return [] }

        return SystemCalendarQuery.enabledResults(in: interval, defaults: defaults)
            .map { CalendarWidgetItem(system: $0, calendar: calendar) }
    }

    @MainActor
    private func holidayRecords(
        for country: HolidayCountry,
        in grid: (monthStart: Date, interval: DateInterval, dates: [Date])
    ) -> [SharedHolidayRecord] {
        switch country {
        case .southKorea:
            return SharedHolidayCache.records(for: country)
        case .unitedStates:
            let calendar = CalendarWidgetCalendar.korean
            let months = Set(grid.dates.compactMap { date -> HolidayMonth? in
                let components = calendar.dateComponents([.year, .month], from: date)
                guard let year = components.year, let month = components.month else {
                    return nil
                }
                return HolidayMonth(year: year, month: month)
            })
            return months.flatMap { USFederalHolidayCalculator.records(for: $0) }
        }
    }
}

/// Provider 내부에서 로컬/시스템 일정을 같은 기준으로 정렬·배치하기 위한 중간 값.
/// 위젯 엔트리 모델(CalendarWidgetOccurrence/Event)과 레이아웃 규칙은 그대로 사용한다.
private struct CalendarWidgetItem {
    let isAllDay: Bool
    let startDate: Date
    let widgetOccurrence: CalendarWidgetOccurrence
    let widgetEvent: CalendarWidgetEvent
    let occurs: (Date, Calendar) -> Bool

    /// 기존 위젯과 동일한 ID/색상 이름 규칙을 그대로 사용한다.
    init(local occurrence: EventOccurrence, calendar: Calendar) {
        let id = "\(occurrence.event.id.uuidString)-\(occurrence.startDate.timeIntervalSince1970)"
        let occupiedRange = occurrence.occupiedDayRange(calendar: calendar)

        isAllDay = occurrence.isAllDay
        startDate = occurrence.isAllDay
            ? AllDayDate.normalizedStorageDate(occurrence.startDate)
            : occurrence.startDate
        widgetOccurrence = CalendarWidgetOccurrence(
            id: id,
            title: occurrence.event.title,
            colorName: occurrence.event.color,
            firstDay: occupiedRange.lowerBound,
            lastDay: occupiedRange.upperBound
        )
        widgetEvent = CalendarWidgetEvent(
            id: id,
            title: occurrence.event.title,
            colorName: occurrence.event.color
        )
        occurs = { occurrence.occurs(on: $0, calendar: $1) }
    }

    /// 시스템 일정은 원본 캘린더 색(systemColor)을 사용하고, 변환할 수 없으면 기본 회색이 된다.
    init(system result: SystemCalendarQuery.Result, calendar: Calendar) {
        let occurrence = result.occurrence
        let occupiedRange = occurrence.occupiedDayRange(calendar: calendar)
        let systemColor = CalendarWidgetSystemColor(cgColor: result.calendarColor)

        isAllDay = occurrence.isAllDay
        startDate = occurrence.startDate
        widgetOccurrence = CalendarWidgetOccurrence(
            id: occurrence.id,
            title: occurrence.title,
            colorName: "",
            firstDay: occupiedRange.lowerBound,
            lastDay: occupiedRange.upperBound,
            systemColor: systemColor
        )
        widgetEvent = CalendarWidgetEvent(
            id: occurrence.id,
            title: occurrence.title,
            colorName: "",
            systemColor: systemColor
        )
        occurs = { occurrence.occurs(on: $0, calendar: $1) }
    }

    /// 앱(CalendarDisplayOccurrence.merged)과 같은 기준: 종일 우선, 시작 시각 순.
    /// 시스템 일정이 없으면 로컬 결과를 그대로 반환해 기존 순서를 보존한다.
    static func merged(
        local: [CalendarWidgetItem],
        system: [CalendarWidgetItem]
    ) -> [CalendarWidgetItem] {
        guard !system.isEmpty else { return local }

        return (local + system).sorted { first, second in
            if first.isAllDay != second.isAllDay {
                return first.isAllDay
            }

            return first.startDate < second.startDate
        }
    }
}
