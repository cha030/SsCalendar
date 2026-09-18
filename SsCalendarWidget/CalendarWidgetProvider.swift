import SwiftData
import WidgetKit

struct CalendarWidgetProvider: TimelineProvider {
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
            let calendar = CalendarWidgetCalendar.korean
            let nextMidnight = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: now)
            ) ?? now.addingTimeInterval(86_400)
            completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
        }
    }

    @MainActor
    private func loadEntry(for date: Date) -> CalendarWidgetEntry {
        let displayedMonth = WidgetMonthState.displayedMonthStart(now: date)
        let grid = CalendarWidgetCalendar.monthGrid(containing: displayedMonth)
        let calendar = CalendarWidgetCalendar.korean
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
            let holidaysByDate = Dictionary(grouping: SharedHolidayCache.records()) {
                calendar.startOfDay(for: $0.date)
            }
            let widgetOccurrences = occurrences.map { occurrence in
                let occupiedRange = occurrence.occupiedDayRange(calendar: calendar)
                return CalendarWidgetOccurrence(
                    id: "\(occurrence.event.id.uuidString)-\(occurrence.startDate.timeIntervalSince1970)",
                    title: occurrence.event.title,
                    colorName: occurrence.event.color,
                    firstDay: occupiedRange.lowerBound,
                    lastDay: occupiedRange.upperBound
                )
            }

            let days = grid.dates.map { day in
                let holidays = (holidaysByDate[calendar.startOfDay(for: day)] ?? [])
                    .filter(\.isHoliday)
                let dayEvents = occurrences
                    .filter { $0.occurs(on: day, calendar: calendar) }
                    .map { occurrence in
                        CalendarWidgetEvent(
                            id: "\(occurrence.event.id.uuidString)-\(occurrence.startDate.timeIntervalSince1970)",
                            title: occurrence.event.title,
                            colorName: occurrence.event.color
                        )
                    }

                return CalendarWidgetDay(
                    date: day,
                    isCurrentMonth: calendar.isDate(day, equalTo: grid.monthStart, toGranularity: .month),
                    isToday: calendar.isDateInToday(day),
                    isHoliday: !holidays.isEmpty,
                    holidayTitle: HolidayDisplayFormatter.title(
                        for: holidays.map(\.name),
                        on: day
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
}
