import Foundation
import SwiftUI
import Testing

@testable import SsCalendar

/// 잠금화면 Today/Next 위젯의 일정 판별 로직(TodayWidgetStatusResolver) 테스트.
/// EventKit·SwiftData·WidgetKit 없이 순수 값만으로 검증한다.
@Suite("TodayWidgetStatusResolver")
struct TodayWidgetStatusResolverTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    /// 모든 테스트 시각은 이 날짜(2026-01-15, 임의의 고정일) 기준 상대 시각이다.
    /// 실행 시점의 실제 "지금"과 무관하게 항상 같은 결과를 내기 위함이다.
    private var dayStart: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
    }

    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: dayStart)!
    }

    private func occurrence(
        id: String,
        isAllDay: Bool = false,
        start: Date,
        end: Date
    ) -> CalendarDisplayOccurrence {
        CalendarDisplayOccurrence(
            id: id,
            source: .local(eventID: UUID()),
            title: id,
            isAllDay: isAllDay,
            startDate: start,
            endDate: end,
            color: .clear
        )
    }

    @Test("오늘 일정이 전혀 없으면 Today·Next 모두 비어 있다")
    func noEventsToday() {
        let status = TodayWidgetStatusResolver.status(from: [], now: time(10), calendar: calendar)
        #expect(status.today == nil)
        #expect(status.next == nil)
        #expect(!status.isTodayOngoing)
    }

    @Test("진행 중인 일정이 없으면 Today는 가장 가까운 예정 일정을 대신 보여준다")
    func todayFallsBackToNearestUpcomingWhenNothingOngoing() {
        let upcoming = occurrence(id: "upcoming", start: time(14), end: time(15))
        let status = TodayWidgetStatusResolver.status(from: [upcoming], now: time(10), calendar: calendar)
        #expect(status.today?.id == "upcoming")
        #expect(!status.isTodayOngoing)
        #expect(status.next == nil)
    }

    @Test("진행 중인 일정이 있으면 Today가 진행 중으로 표시한다")
    func todayShowsOngoingEvent() {
        let ongoing = occurrence(id: "ongoing", start: time(9), end: time(11))
        let status = TodayWidgetStatusResolver.status(from: [ongoing], now: time(10), calendar: calendar)
        #expect(status.today?.id == "ongoing")
        #expect(status.isTodayOngoing)
        #expect(status.next == nil)
    }

    @Test("Today가 진행 중인 일정을 보여줄 때 Next는 그다음 일정을 보여준다")
    func todayOngoingAndNextUpcoming() {
        let ongoing = occurrence(id: "ongoing", start: time(9), end: time(11))
        let upcoming = occurrence(id: "upcoming", start: time(14), end: time(15))
        let status = TodayWidgetStatusResolver.status(
            from: [ongoing, upcoming],
            now: time(10),
            calendar: calendar
        )
        #expect(status.today?.id == "ongoing")
        #expect(status.isTodayOngoing)
        #expect(status.next?.id == "upcoming")
    }

    @Test("Today와 Next는 서로 다른 일정을 가리키며 중복되지 않는다")
    func todayAndNextNeverDuplicate() {
        let a = occurrence(id: "a", start: time(14), end: time(15))
        let b = occurrence(id: "b", start: time(16), end: time(17))
        let status = TodayWidgetStatusResolver.status(from: [a, b], now: time(10), calendar: calendar)
        #expect(status.today?.id == "a")
        #expect(status.next?.id == "b")
        #expect(status.today?.id != status.next?.id)
    }

    @Test("명세 예시 그대로: 병원 진료·친구 약속 두 일정의 하루 흐름")
    func specExampleWalkthrough() {
        let hospital = occurrence(id: "hospital", start: time(14), end: time(15))
        let friend = occurrence(id: "friend", start: time(16), end: time(17))
        let occurrences = [hospital, friend]

        // 10:00 → Today: 14:00 병원 진료(예정), Next: 16:00 친구 약속
        let at10 = TodayWidgetStatusResolver.status(from: occurrences, now: time(10), calendar: calendar)
        #expect(at10.today?.id == "hospital")
        #expect(!at10.isTodayOngoing)
        #expect(at10.next?.id == "friend")

        // 14:30 → Today: 진행 14:00 병원 진료, Next: 16:00 친구 약속
        let at1430 = TodayWidgetStatusResolver.status(from: occurrences, now: time(14, 30), calendar: calendar)
        #expect(at1430.today?.id == "hospital")
        #expect(at1430.isTodayOngoing)
        #expect(at1430.next?.id == "friend")

        // 15:30 → Today: 16:00 친구 약속(예정), Next: 없음
        let at1530 = TodayWidgetStatusResolver.status(from: occurrences, now: time(15, 30), calendar: calendar)
        #expect(at1530.today?.id == "friend")
        #expect(!at1530.isTodayOngoing)
        #expect(at1530.next == nil)

        // 16:30 → Today: 진행 16:00 친구 약속, Next: 없음
        let at1630 = TodayWidgetStatusResolver.status(from: occurrences, now: time(16, 30), calendar: calendar)
        #expect(at1630.today?.id == "friend")
        #expect(at1630.isTodayOngoing)
        #expect(at1630.next == nil)

        // 17:00 이후 → Today/Next 모두 없음
        let at17 = TodayWidgetStatusResolver.status(from: occurrences, now: time(17), calendar: calendar)
        #expect(at17.today == nil)
        #expect(at17.next == nil)
    }

    @Test("시간 지정 일정이 전혀 없을 때만 Today가 종일 일정을 보여주며, 이때는 진행 표시가 없다")
    func allDayOnlyIgnoresStoredTimeAndIsNotMarkedOngoing() {
        // 종일 일정의 저장된 시간 값(여기서는 07시)은 의미가 없다는 것을 보이기 위해
        // 그보다 이른 시각(03시)을 now로 사용한다.
        let allDay = occurrence(id: "allDay", isAllDay: true, start: time(7), end: time(8))
        let status = TodayWidgetStatusResolver.status(from: [allDay], now: time(3), calendar: calendar)
        #expect(status.today?.id == "allDay")
        // 종일 일정은 "종일"로 이미 시간 대신 표시되므로 "진행" 배지는 붙지 않는다.
        #expect(!status.isTodayOngoing)
        #expect(status.next == nil)
    }

    @Test("시간 지정 일정이 진행 중이면 종일 일정보다 Today 우선순위가 높다")
    func ongoingTimedEventTakesPriorityOverAllDay() {
        let allDay = occurrence(id: "allDay", isAllDay: true, start: time(0), end: time(0))
        let timed = occurrence(id: "timed", start: time(9), end: time(11))
        let status = TodayWidgetStatusResolver.status(
            from: [allDay, timed],
            now: time(10),
            calendar: calendar
        )
        #expect(status.today?.id == "timed")
        #expect(status.isTodayOngoing)
    }

    @Test("진행 중인 시간 지정 일정이 없어도, 예정된 시간 지정 일정이 있으면 종일 일정보다 우선한다")
    func upcomingTimedEventTakesPriorityOverAllDay() {
        let allDay = occurrence(id: "allDay", isAllDay: true, start: time(0), end: time(0))
        let timed = occurrence(id: "timed", start: time(18), end: time(19))
        let status = TodayWidgetStatusResolver.status(
            from: [allDay, timed],
            now: time(9),
            calendar: calendar
        )
        #expect(status.today?.id == "timed")
        #expect(!status.isTodayOngoing)
        #expect(status.next == nil)
    }

    @Test("명세 예시 그대로: 종일 휴가 + 병원 진료 + 친구 약속의 하루 흐름")
    func specExampleWithAllDayFallback() {
        let vacation = occurrence(id: "vacation", isAllDay: true, start: time(0), end: time(0))
        let hospital = occurrence(id: "hospital", start: time(14), end: time(15))
        let friend = occurrence(id: "friend", start: time(16), end: time(17))
        let occurrences = [vacation, hospital, friend]

        // 10:00 → Today: 14:00 병원 진료, Next: 16:00 친구 약속 (종일 일정은 뒤로 밀린다)
        let at10 = TodayWidgetStatusResolver.status(from: occurrences, now: time(10), calendar: calendar)
        #expect(at10.today?.id == "hospital")
        #expect(!at10.isTodayOngoing)
        #expect(at10.next?.id == "friend")

        // 15:00 이후(15:30) → Today: 16:00 친구 약속, Next: 다음 일정 없음
        let at1530 = TodayWidgetStatusResolver.status(from: occurrences, now: time(15, 30), calendar: calendar)
        #expect(at1530.today?.id == "friend")
        #expect(!at1530.isTodayOngoing)
        #expect(at1530.next == nil)

        // 17:00 이후 → 시간 지정 일정이 모두 끝나 Today가 종일 휴가로 대체되고, 진행 표시는 없다
        let at17 = TodayWidgetStatusResolver.status(from: occurrences, now: time(17), calendar: calendar)
        #expect(at17.today?.id == "vacation")
        #expect(!at17.isTodayOngoing)
        #expect(at17.next == nil)
    }

    @Test("동시에 여러 일정이 진행 중이면 종료가 가장 빠른 일정을 Today 대표로 고른다")
    func picksEarliestEndingAmongConcurrentEvents() {
        let longer = occurrence(id: "longer", start: time(9), end: time(12))
        let shorter = occurrence(id: "shorter", start: time(9, 30), end: time(10, 30))
        let status = TodayWidgetStatusResolver.status(
            from: [longer, shorter],
            now: time(10),
            calendar: calendar
        )
        #expect(status.today?.id == "shorter")
    }

    @Test("시작·종료 시각이 같으면 입력 순서와 무관하게 항상 같은 결과를 고른다")
    func stableTieBreakRegardlessOfInputOrder() {
        let a = occurrence(id: "a", start: time(9), end: time(10))
        let b = occurrence(id: "b", start: time(9), end: time(10))

        let status1 = TodayWidgetStatusResolver.status(from: [a, b], now: time(9, 30), calendar: calendar)
        let status2 = TodayWidgetStatusResolver.status(from: [b, a], now: time(9, 30), calendar: calendar)

        #expect(status1.today?.id == status2.today?.id)
    }

    @Test("자정을 넘기는 진행 중 일정도 기존 교차 판별 규칙대로 오늘의 Today로 표시된다")
    func ongoingEventCrossingMidnightStillCounts() {
        // 어제 23:00에 시작해 오늘 01:00에 끝나는 일정. occurs/intersects 규칙은 그대로이므로
        // 이 occurrence는 "오늘과 겹치는 occurrence" 목록에 이미 포함되어 들어온다고 가정한다.
        let overnight = occurrence(
            id: "overnight",
            start: time(-1), // 전날 23:00
            end: time(1) // 오늘 00:00 이후 01:00
        )
        let status = TodayWidgetStatusResolver.status(from: [overnight], now: time(0, 30), calendar: calendar)
        #expect(status.today?.id == "overnight")
        #expect(status.isTodayOngoing)
    }
}

/// 월간 달력의 Adaptive Event Title(단일 날짜 일정 2줄 확장) 배치 로직(WeekEventLayout) 테스트.
/// 실제 렌더링에 쓰이는 값과 같은 상수(CalendarDayContentLayout.cellHeight 등)로 검증해,
/// 배치 계산 높이와 렌더링 높이가 어긋나지 않는지 확인한다.
@Suite("WeekEventLayout")
struct WeekEventLayoutTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private let rowHeight = CalendarDayContentLayout.cellHeight // 102
    private let eventHeight: CGFloat = 13
    private let twoLineEventHeight: CGFloat = 26
    private let eventSpacing: CGFloat = 1
    private let maximumVisibleEventsPerDay = 4 // 프로덕션(CalendarWeekRow)과 같은 값.
    /// 실제 좁은 날짜 칸(iPhone 세로 모드 기준)을 흉내 낸 제목용 가로 폭.
    /// "발표"/"Call"처럼 짧은 제목은 넉넉히 들어가고, 긴 제목은 분명히 넘치도록 여유를 두고 골랐다.
    private let narrowColumnTextWidth: CGFloat = 60
    /// 가로 모드나 아이패드처럼 칸이 넓은 경우를 흉내 낸 너비. 같은 제목이라도 너비에 따라
    /// 1줄/2줄 판정이 달라짐("Adaptive")을 보여주는 테스트에 쓴다.
    private let wideColumnTextWidth: CGFloat = 220

    /// 임의의 날짜가 속한 주의 일~토 7일을 만든다. 실제 firstWeekday(1) 기준과 같다.
    private var week: CalendarWeek {
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        let dates = (0..<7).map {
            calendar.date(byAdding: .day, value: $0, to: weekStart)!
        }
        return CalendarWeek(dates: dates)
    }

    /// `dayOffset`(0=일요일...6=토요일)의 해당 시각.
    private func time(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(
            byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute),
            to: week.dates[0]
        )!
    }

    private func timedOccurrence(
        id: String,
        title: String? = nil,
        dayOffset: Int,
        startHour: Int,
        endHour: Int
    ) -> CalendarDisplayOccurrence {
        CalendarDisplayOccurrence(
            id: id,
            source: .local(eventID: UUID()),
            title: title ?? id,
            isAllDay: false,
            startDate: time(dayOffset: dayOffset, hour: startHour),
            endDate: time(dayOffset: dayOffset, hour: endHour),
            color: .clear
        )
    }

    private func multiDayOccurrence(
        id: String,
        startDayOffset: Int,
        endDayOffset: Int
    ) -> CalendarDisplayOccurrence {
        CalendarDisplayOccurrence(
            id: id,
            source: .local(eventID: UUID()),
            title: id,
            isAllDay: true,
            startDate: time(dayOffset: startDayOffset, hour: 0),
            endDate: time(dayOffset: endDayOffset, hour: 0),
            color: .clear
        )
    }

    /// `week`를 기준으로 `afterWeeks`주 뒤의 일~토 7일. 주 경계를 넘는 일정을 여러 주에 걸쳐
    /// 각각 검증(매주 별도로 CalendarWeekRow가 WeekEventLayout을 새로 계산하는 실제 구조와 동일)할 때 쓴다.
    private func week(afterWeeks: Int) -> CalendarWeek {
        let start = calendar.date(byAdding: .weekOfYear, value: afterWeeks, to: week.dates[0])!
        let dates = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        return CalendarWeek(dates: dates)
    }

    private func layout(
        occurrences: [CalendarDisplayOccurrence],
        holidaysByDate: [Date: [Holiday]] = [:],
        textWidth: CGFloat? = nil
    ) -> WeekEventLayout {
        layout(occurrences: occurrences, holidaysByDate: holidaysByDate, in: week, textWidth: textWidth)
    }

    private func layout(
        occurrences: [CalendarDisplayOccurrence],
        holidaysByDate: [Date: [Holiday]] = [:],
        in week: CalendarWeek,
        textWidth: CGFloat? = nil
    ) -> WeekEventLayout {
        WeekEventLayout(
            week: week,
            occurrences: occurrences,
            holidaysByDate: holidaysByDate,
            calendar: calendar,
            rowHeight: rowHeight,
            eventHeight: eventHeight,
            twoLineEventHeight: twoLineEventHeight,
            eventSpacing: eventSpacing,
            maximumVisibleEventsPerDay: maximumVisibleEventsPerDay,
            singleDayTextWidth: textWidth ?? narrowColumnTextWidth
        )
    }

    /// 모든 시나리오에서 공통으로 지켜야 할 것: 어떤 세그먼트도 칸 아래로 넘치지 않고,
    /// 같은 날짜(컬럼)를 공유하는 세그먼트끼리는 서로 겹치지 않는다.
    private func assertNoOverflowOrOverlap(_ segments: [WeekEventSegment]) {
        for segment in segments {
            #expect(segment.yOffset + segment.height <= rowHeight)
        }

        for i in segments.indices {
            for j in segments.indices where j > i {
                let a = segments[i]
                let b = segments[j]
                guard a.startColumn <= b.endColumn, a.endColumn >= b.startColumn else { continue }

                let aRange = a.yOffset..<(a.yOffset + a.height)
                let bRange = b.yOffset..<(b.yOffset + b.height)
                #expect(!aRange.overlaps(bRange))
            }
        }
    }

    @Test("평일에 긴 제목의 일정이 하나뿐이면 2줄로 확장된다")
    func singleEventOnWeekdayGetsTwoLines() {
        // dayOffset 2 = 화요일(공휴일·음력 없음). 제목이 narrowColumnTextWidth에 한 줄로 안 들어갈 만큼 길다.
        let event = timedOccurrence(id: "a", title: "디자인팀 전체 회의 준비", dayOffset: 2, startHour: 10, endHour: 11)
        let result = layout(occurrences: [event])

        #expect(result.visibleSegments.count == 1)
        #expect(result.visibleSegments[0].isTwoLine)
        #expect(result.visibleSegments[0].height == twoLineEventHeight)
        #expect(result.overflowCounts[2] == nil)
        assertNoOverflowOrOverlap(result.visibleSegments)
    }

    @Test("하루 3개 일정(모두 긴 제목)은 모두 보이며, 표시 개수를 우선해 제목 길이와 무관하게 전부 1줄로 유지된다")
    func threeEventsSameDayAllVisibleAllStayOneLine() {
        // 셋 다 narrowColumnTextWidth에 한 줄로 안 들어가는 긴 제목이지만, 하루 3개 이상이면
        // "표시 개수" 우선 규칙(denseDayThreshold)이 너비 기반 2줄 판단보다 우선해 전부 1줄이어야 한다.
        let events = [
            timedOccurrence(id: "a", title: "분기 전체 회의 준비", dayOffset: 3, startHour: 9, endHour: 10),
            timedOccurrence(id: "b", title: "분기 전체 회의 준비", dayOffset: 3, startHour: 11, endHour: 12),
            timedOccurrence(id: "c", title: "분기 전체 회의 준비", dayOffset: 3, startHour: 13, endHour: 14)
        ]
        let result = layout(occurrences: events)

        #expect(result.visibleSegments.count == 3)
        #expect(result.overflowCounts[3] == nil)

        let ordered = result.visibleSegments.sorted { $0.yOffset < $1.yOffset }
        #expect(ordered[0].occurrence.id == "a")
        #expect(!ordered[0].isTwoLine)
        #expect(!ordered[1].isTwoLine)
        #expect(!ordered[2].isTwoLine)
        assertNoOverflowOrOverlap(result.visibleSegments)
    }

    @Test("하루 5개 일정 중 첫 제목이 길어도, 표시 개수 우선 규칙 때문에 2줄로 확장되지 않는다")
    func fifthEventDayWithLongFirstTitleStaysOneLineDueToDensity() {
        let events = [
            timedOccurrence(id: "a", title: "분기 전체 회의 준비", dayOffset: 4, startHour: 8, endHour: 9),
            timedOccurrence(id: "b", dayOffset: 4, startHour: 10, endHour: 11),
            timedOccurrence(id: "c", dayOffset: 4, startHour: 12, endHour: 13),
            timedOccurrence(id: "d", dayOffset: 4, startHour: 14, endHour: 15),
            timedOccurrence(id: "e", dayOffset: 4, startHour: 16, endHour: 17)
        ]
        let result = layout(occurrences: events)

        let ordered = result.visibleSegments.sorted { $0.yOffset < $1.yOffset }
        #expect(ordered.allSatisfy { !$0.isTwoLine })
        assertNoOverflowOrOverlap(result.visibleSegments)
    }

    @Test("세로 공간이 넉넉하면 하루 5개 일정 중 4개까지 보이고 다섯 번째는 +N으로 넘어간다")
    func fifthEventOverflowsWhenFourFitButFirstFourStaySafe() throws {
        let events = [
            timedOccurrence(id: "a", dayOffset: 4, startHour: 8, endHour: 9),
            timedOccurrence(id: "b", dayOffset: 4, startHour: 10, endHour: 11),
            timedOccurrence(id: "c", dayOffset: 4, startHour: 12, endHour: 13),
            timedOccurrence(id: "d", dayOffset: 4, startHour: 14, endHour: 15),
            timedOccurrence(id: "e", dayOffset: 4, startHour: 16, endHour: 17)
        ]
        let result = layout(occurrences: events)

        #expect(result.visibleSegments.count == 4)
        #expect(result.overflowCounts[4] == 1)
        assertNoOverflowOrOverlap(result.visibleSegments)

        // "+N"이 보이는 일정과 겹치지 않도록, 가장 아래 보이는 일정보다 아래(또는 칸 안)에 와야 한다.
        let bottomMost = result.visibleSegments
            .filter { $0.startColumn <= 4 && $0.endColumn >= 4 }
            .map { $0.yOffset + $0.height }
            .max() ?? 0
        let overflowY = try #require(result.overflowYOffsets[4])
        #expect(overflowY >= bottomMost - 0.01)
        #expect(overflowY + eventHeight <= rowHeight)
    }

    @Test("세로 공간이 부족하면 하루 5개 일정이라도 3개까지만 보이고 나머지 2개는 +N으로 안전하게 넘어간다")
    func fifthEventFallsBackToThreeVisibleWhenRoomIsTight() throws {
        // 공휴일 1줄 표시(5자 이하라 둘로 안 쪼개짐)로 세로 공간을 적당히 줄인다.
        // 일요일(음력 표시)은 피해서 "공휴일 2줄+음력"처럼 과하게 좁아지는 경우와는 구분한다.
        let wednesday = week.dates[3]
        let holidays: [Date: [Holiday]] = [
            calendar.startOfDay(for: wednesday): [
                Holiday(date: wednesday, name: "휴일", isHoliday: true)
            ]
        ]
        let events = [
            timedOccurrence(id: "a", dayOffset: 3, startHour: 8, endHour: 9),
            timedOccurrence(id: "b", dayOffset: 3, startHour: 10, endHour: 11),
            timedOccurrence(id: "c", dayOffset: 3, startHour: 12, endHour: 13),
            timedOccurrence(id: "d", dayOffset: 3, startHour: 14, endHour: 15),
            timedOccurrence(id: "e", dayOffset: 3, startHour: 16, endHour: 17)
        ]
        let result = layout(occurrences: events, holidaysByDate: holidays)

        #expect(result.visibleSegments.count == 3)
        #expect(result.overflowCounts[3] == 2)
        assertNoOverflowOrOverlap(result.visibleSegments)
    }

    @Test("여러 날에 걸친 일정은 항상 1줄 고정 높이를 유지하고, 같은 날의 단일 일정은 그 아래로 밀려 배치된다")
    func multiDayEventStaysOneLineAndSingleDayStacksBelow() throws {
        let multiDay = multiDayOccurrence(id: "trip", startDayOffset: 1, endDayOffset: 3)
        let single = timedOccurrence(id: "meeting", dayOffset: 2, startHour: 10, endHour: 11)
        let result = layout(occurrences: [multiDay, single])

        let multiDaySegment = try #require(result.visibleSegments.first { $0.occurrence.id == "trip" })
        #expect(!multiDaySegment.isTwoLine)
        #expect(multiDaySegment.height == eventHeight)
        #expect(multiDaySegment.showsTitle) // 한 주 안에서 시작하고 끝나는 일정도 제목이 보여야 한다.

        let singleSegment = try #require(result.visibleSegments.first { $0.occurrence.id == "meeting" })
        #expect(singleSegment.yOffset >= multiDaySegment.yOffset + multiDaySegment.height)
        assertNoOverflowOrOverlap(result.visibleSegments)
    }

    @Test("공휴일 2줄 표시로 세로 공간이 부족하면, 제목이 길어 2줄이 필요한 일정도 1줄로 안전하게 되돌아간다")
    func holidaySqueezeForcesOneLineFallback() {
        // dayOffset 0 = 일요일(항상 음력 표시 대상). HolidayDisplayFormatter는 "(" 없이 5자를 넘는
        // 이름을 가운데에서 둘로 쪼개 2줄로 보여주므로, 7자 이름으로 2줄 공휴일 표시를 유도한다.
        let sunday = week.dates[0]
        let holidays: [Date: [Holiday]] = [
            calendar.startOfDay(for: sunday): [
                Holiday(date: sunday, name: "가나다라마바사", isHoliday: true)
            ]
        ]
        // 제목을 길게 둬서, 1줄로 떨어지는 이유가 "제목이 짧아서"가 아니라 "세로 공간이 부족해서"임을 분명히 한다.
        let event = timedOccurrence(id: "a", title: "분기 전체 회의 준비", dayOffset: 0, startHour: 10, endHour: 11)
        let result = layout(occurrences: [event], holidaysByDate: holidays)

        #expect(result.visibleSegments.count == 1)
        #expect(!result.visibleSegments[0].isTwoLine)
        #expect(result.visibleSegments[0].height == eventHeight)
        assertNoOverflowOrOverlap(result.visibleSegments)
    }

    @Test("일정이 없는 날짜는 빈 배치 결과를 낸다")
    func noEventsProducesEmptySegments() {
        let result = layout(occurrences: [])
        #expect(result.visibleSegments.isEmpty)
        #expect(result.overflowCounts.isEmpty)
    }

    // MARK: - 주 경계를 넘는 일정의 제목 표시(회귀 테스트)
    //
    // CalendarWeekRow는 주마다 WeekEventLayout을 따로 계산하므로, 아래 테스트들은 실제 구조와 똑같이
    // 같은 occurrence를 여러 CalendarWeek(week(afterWeeks:))에 각각 넣어 호출한다.

    @Test("금요일에 시작해 다음 주 수요일에 끝나는 일정은 두 주 모두 막대 시작 칸에 제목을 보여준다")
    func multiWeekEventShowsTitleOnEachWeeksSegment() throws {
        // dayOffset 5 = 이번 주 금요일, dayOffset 10(=7+3) = 다음 주 수요일.
        let trip = multiDayOccurrence(id: "trip", startDayOffset: 5, endDayOffset: 10)

        let firstWeekResult = layout(occurrences: [trip])
        let firstWeekSegment = try #require(
            firstWeekResult.visibleSegments.first { $0.occurrence.id == "trip" }
        )
        #expect(firstWeekSegment.showsTitle)
        #expect(firstWeekSegment.startColumn == 5) // 실제 시작일인 금요일 칸

        let secondWeekResult = layout(occurrences: [trip], in: week(afterWeeks: 1))
        let secondWeekSegment = try #require(
            secondWeekResult.visibleSegments.first { $0.occurrence.id == "trip" }
        )
        #expect(secondWeekSegment.showsTitle)
        #expect(secondWeekSegment.startColumn == 0) // 이어지는 주는 일요일부터 시작하는 막대
        #expect(secondWeekSegment.endColumn == 3) // 수요일에 끝남
    }

    @Test("3주 이상 이어지는 일정은 거쳐 가는 모든 주의 막대 시작 칸에 제목을 보여준다")
    func threeWeekSpanningEventShowsTitleOnEveryWeek() throws {
        // dayOffset 1(월, 0주차) ~ dayOffset 16(화, 2주차: 7*2+2) = 3주에 걸친 일정.
        let trip = multiDayOccurrence(id: "long-trip", startDayOffset: 1, endDayOffset: 16)

        let week0 = try #require(layout(occurrences: [trip]).visibleSegments.first)
        #expect(week0.showsTitle)
        #expect(week0.startColumn == 1) // 실제 시작일인 월요일

        let week1 = try #require(
            layout(occurrences: [trip], in: week(afterWeeks: 1)).visibleSegments.first
        )
        #expect(week1.showsTitle)
        #expect(week1.startColumn == 0)
        #expect(week1.endColumn == 6) // 둘째 주는 끝까지 이어짐

        let week2 = try #require(
            layout(occurrences: [trip], in: week(afterWeeks: 2)).visibleSegments.first
        )
        #expect(week2.showsTitle)
        #expect(week2.startColumn == 0)
        #expect(week2.endColumn == 2) // 화요일에 끝남
    }

    @Test("월 경계를 넘는 일정도 현재 표시 중인 주 구간의 시작 칸에 제목을 보여준다")
    func monthBoundaryEventShowsTitleAtWeekStart() throws {
        // 1월 마지막 주(1월 안에서 시작)와 2월로 넘어가는 다음 주를 직접 구성한다.
        let januaryAnchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 28))!
        let week0Start = calendar.dateInterval(of: .weekOfYear, for: januaryAnchor)!.start
        let week0 = CalendarWeek(
            dates: (0..<7).map { calendar.date(byAdding: .day, value: $0, to: week0Start)! }
        )
        let week1 = CalendarWeek(
            dates: (0..<7).map { calendar.date(byAdding: .day, value: 7 + $0, to: week0Start)! }
        )

        // week0의 화요일(1월)에 시작해 week1의 목요일(2월)에 끝나는 종일 일정.
        let trip = CalendarDisplayOccurrence(
            id: "month-crossing",
            source: .local(eventID: UUID()),
            title: "month-crossing",
            isAllDay: true,
            startDate: calendar.date(byAdding: .day, value: 2, to: week0Start)!,
            endDate: calendar.date(byAdding: .day, value: 7 + 4, to: week0Start)!,
            color: .clear
        )

        let week0Segment = try #require(
            layout(occurrences: [trip], in: week0).visibleSegments.first
        )
        #expect(week0Segment.showsTitle)
        #expect(week0Segment.startColumn == 2)

        let week1Segment = try #require(
            layout(occurrences: [trip], in: week1).visibleSegments.first
        )
        #expect(week1Segment.showsTitle)
        #expect(week1Segment.startColumn == 0) // 2월로 넘어온 주는 일요일부터 시작하는 막대
    }

    @Test("실제로 일요일에 시작하는 여러 날 일정도 제목이 표시된다")
    func eventActuallyStartingOnSundayShowsTitle() throws {
        let event = multiDayOccurrence(id: "sunday-start", startDayOffset: 0, endDayOffset: 2)
        let segment = try #require(layout(occurrences: [event]).visibleSegments.first)
        #expect(segment.showsTitle)
        #expect(segment.startColumn == 0)
    }

    // MARK: - 제목 너비 기반 1줄/2줄 판정(회귀 테스트)
    //
    // 글자 수가 아니라 실제 폰트 기준 렌더링 너비로 판단하는지 확인한다. 세로 공간은 항상
    // 넉넉한 요일(화요일, dayOffset 2, 공휴일·음력 없음)을 써서 "세로 공간은 충분한데도
    // 제목이 짧아 2줄로 늘어나지 않는지"만 순수하게 검증한다.

    @Test("짧은 한글 제목('발표', '월세')은 세로 공간이 남아도 1줄 높이를 그대로 쓴다")
    func shortKoreanTitlesStayOneLine() {
        for title in ["발표", "월세"] {
            let event = timedOccurrence(id: title, title: title, dayOffset: 2, startHour: 10, endHour: 11)
            let result = layout(occurrences: [event])

            #expect(result.visibleSegments.count == 1)
            #expect(!result.visibleSegments[0].isTwoLine)
            #expect(result.visibleSegments[0].height == eventHeight)
        }
    }

    @Test("짧은 영어 제목('Call')은 한 줄에 들어가면 1줄 높이를 그대로 쓴다")
    func shortEnglishTitleFitsOnOneLine() {
        let event = timedOccurrence(id: "call", title: "Call", dayOffset: 2, startHour: 10, endHour: 11)
        let result = layout(occurrences: [event])

        #expect(!result.visibleSegments[0].isTwoLine)
        #expect(result.visibleSegments[0].height == eventHeight)
    }

    @Test("같은 제목이라도 칸이 넓으면 1줄, 좁으면 2줄로 — 단어 길이를 고려한 실제 너비로 판단한다")
    func sameTitleAdaptsToAvailableWidth() {
        let event = timedOccurrence(id: "meeting", title: "Client Meeting", dayOffset: 2, startHour: 10, endHour: 11)

        let wide = layout(occurrences: [event], textWidth: wideColumnTextWidth)
        #expect(!wide.visibleSegments[0].isTwoLine, "충분히 넓은 칸에서는 한 줄로 다 들어가야 한다")

        let narrow = layout(occurrences: [event], textWidth: narrowColumnTextWidth)
        #expect(narrow.visibleSegments[0].isTwoLine, "좁은 칸에서는 같은 제목도 2줄이 필요하다")
    }

    @Test("긴 영어 제목은 세로 공간이 있으면 최대 2줄까지 확장된다")
    func longEnglishTitleExpandsToTwoLinesWhenRoomAllows() {
        let event = timedOccurrence(
            id: "meeting",
            title: "Meeting with Michael",
            dayOffset: 2,
            startHour: 10,
            endHour: 11
        )
        let result = layout(occurrences: [event])

        #expect(result.visibleSegments[0].isTwoLine)
        #expect(result.visibleSegments[0].height == twoLineEventHeight)
    }

    @Test("아주 긴 영어 제목도 2줄까지만 확장되고 그 이상 늘어나지 않는다(나머지는 Text의 말줄임이 처리)")
    func veryLongEnglishTitleStillCapsAtTwoLines() {
        let event = timedOccurrence(
            id: "long",
            title: "Quarterly Business Review And Strategy Planning Session",
            dayOffset: 2,
            startHour: 10,
            endHour: 11
        )
        let result = layout(occurrences: [event])

        #expect(result.visibleSegments[0].isTwoLine)
        #expect(result.visibleSegments[0].height == twoLineEventHeight) // 2줄 이상으로는 늘어나지 않는다.
    }
}

@Suite("YearMiniMonthGrid")
struct YearMiniMonthGridTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private func day(_ date: Date?) -> Int? {
        guard let date else { return nil }
        return calendar.component(.day, from: date)
    }

    @Test("항상 42칸(6행×7열)을 만든다")
    func alwaysProducesFortyTwoCells() {
        let grid = YearMiniMonthGrid(year: 2026, month: 1, calendar: calendar)
        #expect(grid.days.count == 42)
    }

    @Test("2026년 1월 1일은 목요일이라 앞에 4칸의 공백(일~수)이 와야 한다")
    func januaryTwentyTwentySixStartsOnThursday() {
        // 2026-01-01은 목요일(일요일 시작 기준으로 0=일,1=월,2=화,3=수,4=목 → 앞 공백 4칸).
        let grid = YearMiniMonthGrid(year: 2026, month: 1, calendar: calendar)

        #expect(grid.days[0] == nil)
        #expect(grid.days[1] == nil)
        #expect(grid.days[2] == nil)
        #expect(grid.days[3] == nil)
        #expect(day(grid.days[4]) == 1)
        #expect(day(grid.days[34]) == 31) // 4(앞 공백) + 31(마지막 날) - 1 = 34
        #expect(grid.days[35] == nil) // 31일 이후로는 다시 공백
    }

    @Test("윤년 2024년 2월은 29일까지 정확히 표시되고 2025년 2월은 28일까지만 표시된다")
    func leapYearFebruaryShowsTwentyNineDaysNonLeapShowsTwentyEight() {
        let leapGrid = YearMiniMonthGrid(year: 2024, month: 2, calendar: calendar)
        let nonLeapGrid = YearMiniMonthGrid(year: 2025, month: 2, calendar: calendar)

        let leapDayCount = leapGrid.days.compactMap { $0 }.count
        let nonLeapDayCount = nonLeapGrid.days.compactMap { $0 }.count

        #expect(leapDayCount == 29)
        #expect(nonLeapDayCount == 28)

        let leapLastDay = leapGrid.days.compactMap(day).max()
        let nonLeapLastDay = nonLeapGrid.days.compactMap(day).max()
        #expect(leapLastDay == 29)
        #expect(nonLeapLastDay == 28)
    }

    @Test("연말(12월)과 연초(1월) 경계에서도 각 달의 날짜 수가 정확하다")
    func yearBoundaryMonthsHaveCorrectDayCounts() {
        let december = YearMiniMonthGrid(year: 2026, month: 12, calendar: calendar)
        let january = YearMiniMonthGrid(year: 2027, month: 1, calendar: calendar)

        #expect(december.days.compactMap { $0 }.count == 31)
        #expect(january.days.compactMap { $0 }.count == 31)
    }

    @Test("모든 달에서 그리드 칸 위치(요일 열)가 실제 요일과 일치한다")
    func everyCellsColumnMatchesItsActualWeekday() {
        // 1~12월을 모두 훑어, nil이 아닌 각 칸의 실제 요일이 그 칸의 열 위치(0=일~6=토)와
        // 맞는지 확인한다. 윤년 2월(2024)도 포함해 월 경계·요일 정렬 둘 다 검증한다.
        for month in 1...12 {
            let grid = YearMiniMonthGrid(year: 2024, month: month, calendar: calendar)

            for (index, date) in grid.days.enumerated() {
                guard let date else { continue }
                let column = index % YearMiniMonthGrid.columnCount
                let weekday = calendar.component(.weekday, from: date) // 1=일...7=토
                #expect(weekday - 1 == column)
            }
        }
    }
}
