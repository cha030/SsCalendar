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
