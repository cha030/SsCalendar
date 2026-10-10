import Foundation

struct EventOccurrence: Identifiable {
    struct ID: Hashable {
        let eventID: UUID
        let startDate: Date
    }

    let event: Event
    let startDate: Date
    let endDate: Date
    /// 반복 규칙이 원래 계산한 시작 시각(override 이전). 예외 식별과 "원본 발생일 기준" 처리에
    /// 쓰인다. 개별 수정(override)되지 않은 발생분은 startDate와 같다.
    let originalStartDate: Date
    /// 이 발생분에 적용된 개별 수정(override) 예외(Step 5-2). nil이면 원본 Event 값을 그대로 쓴다.
    let exception: EventOccurrenceException?

    init(
        event: Event,
        startDate: Date,
        endDate: Date,
        originalStartDate: Date? = nil,
        exception: EventOccurrenceException? = nil
    ) {
        self.event = event
        self.startDate = startDate
        self.endDate = endDate
        self.originalStartDate = originalStartDate ?? startDate
        self.exception = exception
    }

    var id: ID {
        ID(eventID: event.id, startDate: startDate)
    }

    var title: String {
        exception?.overrideTitle ?? event.title
    }

    var colorName: String {
        exception?.overrideColor ?? event.color
    }

    var isAllDay: Bool {
        exception?.overrideIsAllDay ?? event.isAllDay
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
        calendar: Calendar,
        exceptions: [EventOccurrenceException] = []
    ) -> [EventOccurrence] {
        let exceptionsByEventID = Dictionary(grouping: exceptions, by: \.eventID)
        return events
            .flatMap { event in
                occurrences(
                    for: event,
                    intersecting: range,
                    calendar: calendar,
                    exceptions: exceptionsByEventID[event.id] ?? []
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
        limit: Int? = nil,
        exceptions: [EventOccurrenceException] = []
    ) -> [EventOccurrence] {
        let interval = max(1, event.repeatInterval)
        let duration = max(0, event.endDate.timeIntervalSince(event.startDate))

        let supportedRepeatUnits = ["일", "주", "개월", "년"]
        guard supportedRepeatUnits.contains(event.repeatUnit) else {
            // 반복하지 않는 일정은 개별 수정·삭제 예외 대상이 아니다(반복 일정에만 적용).
            let occurrence = EventOccurrence(
                event: event,
                startDate: event.startDate,
                endDate: event.endDate
            )
            return occurrence.intersects(range, calendar: calendar)
                ? [occurrence]
                : []
        }

        // 반복 종료일(포함)을 하루 끝 기준으로 미리 구해 둔다. 날짜만 비교하므로 종료일 당일의
        // 발생분은 시각과 무관하게 항상 포함된다.
        let repeatEndDay = event.repeatEndDate.map { calendar.startOfDay(for: $0) }
        let exceptionsByKey = Dictionary(
            exceptions.map { (exceptionKey(for: $0.originalOccurrenceStartDate), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var results: [EventOccurrence] = []
        var occurrenceIndex = 0
        let maximumIterations = 500_000

        while occurrenceIndex < maximumIterations {
            guard let occurrenceStart = recurrenceDate(
                startDate: event.startDate,
                repeatUnit: event.repeatUnit,
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

            // 반복 종료일을 지난 발생분은 더 만들지 않는다(종료일 당일까지는 포함). 이 판단은
            // 항상 "원래" 발생일(occurrenceStart) 기준이다 — override로 날짜를 옮겼어도 반복
            // 시리즈 자체의 종료 조건은 원본 슬롯 기준으로 일관되게 적용한다.
            if let repeatEndDay, calendar.startOfDay(for: occurrenceStart) > repeatEndDay {
                break
            }

            if let exception = exceptionsByKey[exceptionKey(for: occurrenceStart)] {
                if !exception.isExcluded {
                    let occurrence = EventOccurrence(
                        event: event,
                        startDate: exception.overrideStartDate,
                        endDate: exception.overrideEndDate,
                        originalStartDate: occurrenceStart,
                        exception: exception
                    )

                    if occurrence.intersects(range, calendar: calendar) {
                        results.append(occurrence)

                        if let limit, results.count >= limit {
                            break
                        }
                    }
                }
                // isExcluded == true: 개별 삭제된 발생분이라 아무것도 만들지 않는다.
            } else {
                let occurrence = EventOccurrence(
                    event: event,
                    startDate: occurrenceStart,
                    endDate: occurrenceStart.addingTimeInterval(duration),
                    originalStartDate: occurrenceStart
                )

                if occurrence.intersects(range, calendar: calendar) {
                    results.append(occurrence)

                    if let limit, results.count >= limit {
                        break
                    }
                }
            }

            occurrenceIndex += 1
        }

        return results
    }

    /// 예외(EventOccurrenceException) 매칭 키. 부동소수점 오차로 같은 발생일이 다르게 매칭되지
    /// 않도록 초 단위로 반올림한다 — originalOccurrenceStartDate는 항상 이 서비스가 계산한
    /// 값을 그대로 저장하므로(EventEditorView), 정상적인 경우 오차가 생기지 않는다.
    private static func exceptionKey(for date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded())
    }

    private static func recurrenceDate(
        startDate: Date,
        repeatUnit: String,
        occurrenceIndex: Int,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        let step = occurrenceIndex * interval

        switch repeatUnit {
        case "일":
            return calendar.date(
                byAdding: .day,
                value: step,
                to: startDate
            )
        case "주":
            return calendar.date(
                byAdding: .weekOfYear,
                value: step,
                to: startDate
            )
        case "개월":
            return monthlyDate(
                from: startDate,
                monthOffset: step,
                calendar: calendar
            )
        case "년":
            return yearlyDate(
                from: startDate,
                yearOffset: step,
                calendar: calendar
            )
        default:
            return occurrenceIndex == 0 ? startDate : nil
        }
    }

    /// 반복 일정이 `now`(포함) 이후 다음으로 발생하는 날짜를 찾는다(Step 5-2 반복 일정 D-Day 정책).
    /// 반복하지 않는 일정이면 nil — 호출하는 쪽에서 event.startDate를 그대로 쓰면 된다.
    ///
    /// `repeatEndDate`를 지정하면(포함) 그 날짜를 지난 발생분은 찾지 않고 nil을 반환한다 — 반복이
    /// 끝난 것과 "다음 발생을 못 찾음"을 호출하는 쪽에서 구분할 필요가 없도록(둘 다 nil이면
    /// event.startDate로 돌아가고, 그 값은 보통 과거라 D-Day 위젯 등에서 자연히 제외된다).
    /// `repeatEndDate`가 nil이면(기본값) 기존처럼 안전 상한(500,000회)까지 계속 찾는다.
    static func nextOccurrenceDate(
        startDate: Date,
        repeatUnit: String,
        repeatInterval: Int,
        onOrAfter now: Date,
        calendar: Calendar,
        repeatEndDate: Date? = nil,
        exceptions: [EventOccurrenceException] = []
    ) -> Date? {
        let supportedRepeatUnits = ["일", "주", "개월", "년"]
        guard supportedRepeatUnits.contains(repeatUnit) else { return nil }

        let interval = max(1, repeatInterval)
        let todayStart = calendar.startOfDay(for: now)
        let repeatEndDay = repeatEndDate.map { calendar.startOfDay(for: $0) }
        let exceptionsByKey = Dictionary(
            exceptions.map { (exceptionKey(for: $0.originalOccurrenceStartDate), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let maximumIterations = 500_000
        var occurrenceIndex = 0

        while occurrenceIndex < maximumIterations {
            guard let occurrenceStart = recurrenceDate(
                startDate: startDate,
                repeatUnit: repeatUnit,
                occurrenceIndex: occurrenceIndex,
                interval: interval,
                calendar: calendar
            ) else {
                occurrenceIndex += 1
                continue
            }

            let occurrenceDay = calendar.startOfDay(for: occurrenceStart)

            if let repeatEndDay, occurrenceDay > repeatEndDay {
                return nil
            }

            if let exception = exceptionsByKey[exceptionKey(for: occurrenceStart)] {
                if !exception.isExcluded {
                    let effectiveDate = exception.overrideStartDate
                    if calendar.startOfDay(for: effectiveDate) >= todayStart {
                        return effectiveDate
                    }
                }
                // isExcluded == true(개별 삭제)면 이 발생분은 건너뛰고 다음 발생분을 찾는다.
            } else if occurrenceDay >= todayStart {
                return occurrenceStart
            }

            occurrenceIndex += 1
        }

        return nil
    }

    /// `Event` 기준 편의 오버로드. event.repeatEndDate(있으면)와 이 시리즈에 해당하는 예외만
    /// 걸러 반영한다.
    static func nextOccurrenceDate(
        for event: Event,
        onOrAfter now: Date,
        calendar: Calendar,
        exceptions: [EventOccurrenceException] = []
    ) -> Date? {
        nextOccurrenceDate(
            startDate: event.startDate,
            repeatUnit: event.repeatUnit,
            repeatInterval: event.repeatInterval,
            onOrAfter: now,
            calendar: calendar,
            repeatEndDate: event.repeatEndDate,
            exceptions: exceptions.filter { $0.eventID == event.id }
        )
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
