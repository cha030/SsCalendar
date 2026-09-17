import Foundation

struct EventOccurrence: Identifiable {
    struct ID: Hashable {
        let eventID: UUID
        let startDate: Date
    }

    let event: Event
    let startDate: Date
    let endDate: Date

    var id: ID {
        ID(eventID: event.id, startDate: startDate)
    }

    var isAllDay: Bool {
        event.isAllDay
    }

    func occurs(on date: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        guard let nextDayStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: dayStart
        ) else {
            return false
        }

        if isAllDay {
            let eventStartDay = calendar.startOfDay(for: startDate)
            let eventEndDay = calendar.startOfDay(for: endDate)
            return eventStartDay <= dayStart && dayStart <= eventEndDay
        }

        if startDate == endDate {
            return startDate >= dayStart && startDate < nextDayStart
        }

        return startDate < nextDayStart && endDate > dayStart
    }

    func occupiedDayRange(calendar: Calendar) -> ClosedRange<Date> {
        let firstDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        if isAllDay || startDate == endDate || endDate > endDay {
            return firstDay...max(firstDay, endDay)
        }

        let previousDay = calendar.date(
            byAdding: .day,
            value: -1,
            to: endDay
        ) ?? firstDay
        return firstDay...max(firstDay, previousDay)
    }

    func intersects(_ range: DateInterval, calendar: Calendar) -> Bool {
        if isAllDay {
            let occupiedDays = occupiedDayRange(calendar: calendar)
            guard let dayAfterLast = calendar.date(
                byAdding: .day,
                value: 1,
                to: occupiedDays.upperBound
            ) else {
                return false
            }

            return occupiedDays.lowerBound < range.end
                && dayAfterLast > range.start
        }

        if startDate == endDate {
            return range.contains(startDate)
        }

        return startDate < range.end && endDate > range.start
    }
}

enum EventOccurrenceService {
    static func occurrences(
        for events: [Event],
        intersecting range: DateInterval,
        calendar: Calendar
    ) -> [EventOccurrence] {
        events
            .flatMap { event in
                occurrences(
                    for: event,
                    intersecting: range,
                    calendar: calendar
                )
            }
            .sorted { first, second in
                if first.isAllDay != second.isAllDay {
                    return first.isAllDay
                }

                return first.startDate < second.startDate
            }
    }

    static func occurrences(
        for event: Event,
        intersecting range: DateInterval,
        calendar: Calendar,
        limit: Int? = nil
    ) -> [EventOccurrence] {
        let interval = max(1, event.repeatInterval)
        let duration = max(0, event.endDate.timeIntervalSince(event.startDate))

        let supportedRepeatUnits = ["일", "주", "개월", "년"]
        guard supportedRepeatUnits.contains(event.repeatUnit) else {
            let occurrence = EventOccurrence(
                event: event,
                startDate: event.startDate,
                endDate: event.endDate
            )
            return occurrence.intersects(range, calendar: calendar)
                ? [occurrence]
                : []
        }

        var results: [EventOccurrence] = []
        var occurrenceIndex = 0
        let maximumIterations = 500_000

        while occurrenceIndex < maximumIterations {
            guard let occurrenceStart = recurrenceDate(
                for: event,
                occurrenceIndex: occurrenceIndex,
                interval: interval,
                calendar: calendar
            ) else {
                occurrenceIndex += 1
                continue
            }

            if occurrenceStart >= range.end {
                break
            }

            let occurrence = EventOccurrence(
                event: event,
                startDate: occurrenceStart,
                endDate: occurrenceStart.addingTimeInterval(duration)
            )

            if occurrence.intersects(range, calendar: calendar) {
                results.append(occurrence)

                if let limit, results.count >= limit {
                    break
                }
            }

            occurrenceIndex += 1
        }

        return results
    }

    private static func recurrenceDate(
        for event: Event,
        occurrenceIndex: Int,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        let step = occurrenceIndex * interval

        switch event.repeatUnit {
        case "일":
            return calendar.date(
                byAdding: .day,
                value: step,
                to: event.startDate
            )
        case "주":
            return calendar.date(
                byAdding: .weekOfYear,
                value: step,
                to: event.startDate
            )
        case "개월":
            return monthlyDate(
                from: event.startDate,
                monthOffset: step,
                calendar: calendar
            )
        case "년":
            return yearlyDate(
                from: event.startDate,
                yearOffset: step,
                calendar: calendar
            )
        default:
            return occurrenceIndex == 0 ? event.startDate : nil
        }
    }

    private static func monthlyDate(
        from startDate: Date,
        monthOffset: Int,
        calendar: Calendar
    ) -> Date? {
        let original = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: startDate
        )

        var monthAnchorComponents = DateComponents()
        monthAnchorComponents.calendar = calendar
        monthAnchorComponents.timeZone = calendar.timeZone
        monthAnchorComponents.year = original.year
        monthAnchorComponents.month = original.month
        monthAnchorComponents.day = 1

        guard
            let monthAnchor = calendar.date(from: monthAnchorComponents),
            let targetMonth = calendar.date(
                byAdding: .month,
                value: monthOffset,
                to: monthAnchor
            )
        else {
            return nil
        }

        let target = calendar.dateComponents([.year, .month], from: targetMonth)
        return validatedDate(
            year: target.year,
            month: target.month,
            day: original.day,
            timeComponents: original,
            calendar: calendar
        )
    }

    private static func yearlyDate(
        from startDate: Date,
        yearOffset: Int,
        calendar: Calendar
    ) -> Date? {
        let original = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: startDate
        )

        guard let originalYear = original.year else {
            return nil
        }

        return validatedDate(
            year: originalYear + yearOffset,
            month: original.month,
            day: original.day,
            timeComponents: original,
            calendar: calendar
        )
    }

    private static func validatedDate(
        year: Int?,
        month: Int?,
        day: Int?,
        timeComponents: DateComponents,
        calendar: Calendar
    ) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        components.nanosecond = timeComponents.nanosecond

        guard components.isValidDate(in: calendar) else {
            return nil
        }

        return calendar.date(from: components)
    }
}
