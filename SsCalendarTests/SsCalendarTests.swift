import Foundation
import EventKit
import SwiftData
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

@Suite("HolidayCountry")
struct HolidayCountryTests {
    @Test("한국은 주말을 색으로 구분하고 미국은 구분하지 않는다")
    func weekendColorPolicy() {
        #expect(HolidayCountry.southKorea.usesColoredWeekends)
        #expect(!HolidayCountry.unitedStates.usesColoredWeekends)
    }

    @Test("지역별 공휴일 국가 기본값을 선택한다")
    func defaultCountryByRegion() {
        #expect(HolidayCountry.defaultCountry(for: Locale.Region("KR")) == .southKorea)
        #expect(HolidayCountry.defaultCountry(for: Locale.Region("US")) == .unitedStates)
        #expect(HolidayCountry.defaultCountry(for: Locale.Region("GB")) == .unitedStates)
        #expect(HolidayCountry.defaultCountry(for: nil) == .unitedStates)
    }
}

@Suite("DeviceCalendar")
struct DeviceCalendarTests {
    @Test("서울과 LA 시간대에서 기기 날짜를 각각 계산한다")
    func deviceDateUsesInjectedTimeZone() {
        let utc = DeviceCalendar.make(timeZone: TimeZone(secondsFromGMT: 0)!)
        let instant = utc.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 6))!
        let seoul = DeviceCalendar.make(timeZone: TimeZone(identifier: "Asia/Seoul")!)
        let losAngeles = DeviceCalendar.make(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

        #expect(seoul.dateComponents([.year, .month, .day], from: instant).day == 22)
        #expect(losAngeles.dateComponents([.year, .month, .day], from: instant).day == 21)
    }

    @Test("LA의 2026-10-22 딥링크 날짜는 22일로 해석된다")
    func deepLinkDateUsesDeviceTimeZone() {
        let calendar = DeviceCalendar.make(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let formatter = DeviceCalendar.dateFormatter(format: "yyyy-MM-dd", calendar: calendar)
        let date = formatter.date(from: "2026-10-22")!

        #expect(calendar.component(.day, from: date) == 22)
        #expect(calendar.component(.month, from: date) == 10)
    }

    @Test("저녁 9시 일정의 D-Day는 기기 시간대의 같은 날짜로 계산된다")
    func eveningEventStaysOnDeviceDate() {
        let calendar = DeviceCalendar.make(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let dayStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let evening = calendar.date(byAdding: .hour, value: 21, to: dayStart)!

        #expect(DDayCalculator.daysRemaining(until: evening, now: evening, calendar: calendar) == 0)
    }

    @Test("LA에서 10월 위젯의 월 이름이 September가 아니다")
    func widgetMonthTitleUsesLosAngelesCalendar() {
        let calendars = [
            DeviceCalendar.make(timeZone: TimeZone(identifier: "Asia/Seoul")!),
            DeviceCalendar.make(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        ]

        for calendar in calendars {
            let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = calendar.locale ?? Locale.current
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MMMM"
            let title = formatter.string(from: october)
            #expect(!title.localizedCaseInsensitiveContains("September"))
            #expect(calendar.component(.month, from: october) == 10)
        }
    }

    @Test("LA에서 위젯 월 그리드가 서울 날짜 기준으로 한 달 이전에 표시되지 않는다")
    func widgetMonthGridUsesInjectedCalendar() {
        let calendars = [
            DeviceCalendar.make(timeZone: TimeZone(identifier: "Asia/Seoul")!),
            DeviceCalendar.make(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        ]

        for calendar in calendars {
            let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
            let monthStart = calendar.dateInterval(of: .month, for: october)!.start
            #expect(calendar.component(.year, from: monthStart) == 2026)
            #expect(calendar.component(.month, from: monthStart) == 10)
        }
    }

    @Test("위젯 Timeline 갱신 시각이 서울과 LA에서 기기 시간대의 다음 자정이다")
    func widgetTimelineRefreshesAtNextDeviceMidnight() {
        let calendars = [
            DeviceCalendar.make(timeZone: TimeZone(identifier: "Asia/Seoul")!),
            DeviceCalendar.make(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        ]
        let now = Date(timeIntervalSince1970: 1_792_938_600)

        for calendar in calendars {
            let dayStart = calendar.startOfDay(for: now)
            let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            #expect(calendar.component(.hour, from: nextMidnight) == 0)
            #expect(calendar.component(.minute, from: nextMidnight) == 0)
            #expect(nextMidnight > now)
            #expect(calendar.component(.day, from: nextMidnight) != calendar.component(.day, from: now))
        }
    }

    @Test("시간대 변경 후 위젯이 서울과 LA의 새 오늘 날짜와 월을 쓴다")
    func widgetUsesNewTimeZoneForTodayAndMonth() {
        let seoul = DeviceCalendar.make(timeZone: TimeZone(identifier: "Asia/Seoul")!)
        let losAngeles = DeviceCalendar.make(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let utc = DeviceCalendar.make(timeZone: TimeZone(secondsFromGMT: 0)!)
        let instant = utc.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 6))!

        let seoulGrid = seoul.dateInterval(of: .month, for: instant)!
        let losAngelesGrid = losAngeles.dateInterval(of: .month, for: instant)!

        #expect(seoul.component(.day, from: instant) == 1)
        #expect(losAngeles.component(.day, from: instant) == 30)
        #expect(seoul.component(.month, from: seoulGrid.start) == 10)
        #expect(losAngeles.component(.month, from: losAngelesGrid.start) == 9)
    }
}

@Suite("USWeekendColorSetting")
struct USWeekendColorSettingTests {

    @Test("미국 주말 색상 설정은 기본값이 무채색이고 저장값을 유지한다")
    func defaultAndPersistence() {
        let defaults = UserDefaults(suiteName: "SsCalendar.USWeekendColorSettingTests.default")!
        defaults.removeObject(forKey: USWeekendColorSetting.storageKey)
        defer { defaults.removeObject(forKey: USWeekendColorSetting.storageKey) }

        #expect(USWeekendColorSetting.selected(in: defaults) == .monochrome)
        #expect(!HolidayCountry.unitedStates.usesColoredWeekends(in: defaults))

        defaults.set(USWeekendColorSetting.colored.rawValue, forKey: USWeekendColorSetting.storageKey)

        #expect(USWeekendColorSetting.selected(in: defaults) == .colored)
        #expect(HolidayCountry.unitedStates.usesColoredWeekends(in: defaults))
        #expect(HolidayCountry.southKorea.usesColoredWeekends(in: defaults))
    }

    @Test("잘못된 미국 주말 색상 설정은 무채색 기본값으로 복원된다")
    func invalidValueFallsBackToMonochrome() {
        let defaults = UserDefaults(suiteName: "SsCalendar.USWeekendColorSettingTests.invalid")!
        defaults.set("invalid", forKey: USWeekendColorSetting.storageKey)
        defer { defaults.removeObject(forKey: USWeekendColorSetting.storageKey) }

        #expect(USWeekendColorSetting.selected(in: defaults) == .monochrome)
        #expect(!HolidayCountry.unitedStates.usesColoredWeekends(in: defaults))
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
        textWidth: CGFloat? = nil,
        holidayTextWidth: CGFloat = 48
    ) -> WeekEventLayout {
        layout(
            occurrences: occurrences,
            holidaysByDate: holidaysByDate,
            in: week,
            textWidth: textWidth,
            holidayTextWidth: holidayTextWidth
        )
    }

    private func layout(
        occurrences: [CalendarDisplayOccurrence],
        holidaysByDate: [Date: [Holiday]] = [:],
        in week: CalendarWeek,
        textWidth: CGFloat? = nil,
        holidayTextWidth: CGFloat = 48
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
            singleDayTextWidth: textWidth ?? narrowColumnTextWidth,
            holidayTextWidth: holidayTextWidth
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

    @Test("일정이 정확히 4개뿐이면(+N 배지가 필요 없음) 4개 모두 보인다")
    func exactlyFourEventsAllVisibleWithNoOverflowBadge() {
        let events = [
            timedOccurrence(id: "a", dayOffset: 4, startHour: 8, endHour: 9),
            timedOccurrence(id: "b", dayOffset: 4, startHour: 10, endHour: 11),
            timedOccurrence(id: "c", dayOffset: 4, startHour: 12, endHour: 13),
            timedOccurrence(id: "d", dayOffset: 4, startHour: 14, endHour: 15)
        ]
        let result = layout(occurrences: events)

        #expect(result.visibleSegments.count == 4)
        #expect(result.overflowCounts[4] == nil)
        assertNoOverflowOrOverlap(result.visibleSegments)
    }

    @Test("""
    하루 5개 일정은 "+N" 배지 한 줄 자리가 필요해 3개까지만 보이고 나머지 2개는 +N으로 넘어간다 \
    (헤더+4개 일정만으로 이미 칸이 꽉 차 배지가 들어갈 자리가 없다 — 실측으로 확인된 물리적 한계)
    """)
    func fifthEventReservesRoomForOverflowBadgeByShowingOnlyThree() throws {
        let events = [
            timedOccurrence(id: "a", dayOffset: 4, startHour: 8, endHour: 9),
            timedOccurrence(id: "b", dayOffset: 4, startHour: 10, endHour: 11),
            timedOccurrence(id: "c", dayOffset: 4, startHour: 12, endHour: 13),
            timedOccurrence(id: "d", dayOffset: 4, startHour: 14, endHour: 15),
            timedOccurrence(id: "e", dayOffset: 4, startHour: 16, endHour: 17)
        ]
        let result = layout(occurrences: events)

        #expect(result.visibleSegments.count == 3)
        #expect(result.overflowCounts[4] == 2)
        assertNoOverflowOrOverlap(result.visibleSegments)

        // "+N" 배지는 보이는 일정과 겹치지 않아야 하고, 102pt 칸 안에도 들어가야 한다 — 이번에
        // 고친 effectiveMaxVisibleByColumn 덕분에 둘 다 만족해야 한다(이전엔 배지 자리를
        // 미리 비워 두지 않아 겹치는 버그가 있었다).
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
        // 이 테스트는 일요일에 음력 줄이 있다고 가정한다. 음력 표시 기본값이 숨김으로 바뀌었으므로
        // 테스트 동안만 켜 두고 끝나면 원래대로 되돌린다.
        LunarDisplaySetting.store.set(true, forKey: LunarDisplaySetting.storageKey)
        defer { LunarDisplaySetting.store.removeObject(forKey: LunarDisplaySetting.storageKey) }

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

    @Test("크리스마스는 좁은 날짜 칸에서 실제 렌더링과 동일하게 2줄 높이를 예약한다")
    func christmasReservesTwoRenderedLinesInNarrowColumn() {
        #expect(
            CalendarDayContentLayout.holidayLineCount(
                for: "크리스마스",
                availableWidth: 48
            ) == 2
        )
        #expect(
            CalendarDayContentLayout.holidayLineCount(
                for: "크리스마스",
                availableWidth: 80
            ) == 1
        )
    }

    @Test("두 줄 공휴일과 일반 일정 두 개는 같은 표시 영역을 사용하지 않는다")
    func wrappedHolidayDoesNotOverlapRegularEvents() throws {
        let thursday = week.dates[4]
        let holidays: [Date: [Holiday]] = [
            calendar.startOfDay(for: thursday): [
                Holiday(date: thursday, name: "기독탄신일", isHoliday: true)
            ]
        ]
        let events = [
            timedOccurrence(id: "a", title: "약속", dayOffset: 4, startHour: 10, endHour: 11),
            timedOccurrence(id: "b", title: "저녁", dayOffset: 4, startHour: 18, endHour: 19)
        ]
        let result = layout(
            occurrences: events,
            holidaysByDate: holidays,
            holidayTextWidth: 48
        )
        let firstEventY = try #require(result.visibleSegments.map(\.yOffset).min())
        let expectedHolidayBottom = CalendarDayContentLayout.dateHeaderHeight
            + (2 * CalendarDayContentLayout.holidayLineHeight)

        #expect(firstEventY >= expectedHolidayBottom + CalendarDayContentLayout.contentSpacing)
        #expect(result.visibleSegments.count == 2)
        assertNoOverflowOrOverlap(result.visibleSegments)
    }

    @Test("일정이 적으면 긴 공휴일은 기존처럼 두 줄을 유지한다")
    func sparseDayKeepsWrappedHolidayAtTwoLines() {
        let thursday = week.dates[4]
        let holidays: [Date: [Holiday]] = [
            calendar.startOfDay(for: thursday): [
                Holiday(date: thursday, name: "크리스마스", isHoliday: true)
            ]
        ]
        let event = timedOccurrence(
            id: "a",
            title: "약속",
            dayOffset: 4,
            startHour: 10,
            endHour: 11
        )
        let result = layout(
            occurrences: [event],
            holidaysByDate: holidays,
            holidayTextWidth: 48
        )

        #expect(result.holidayLineCounts[4] == 2)
        #expect(result.visibleSegments.count == 1)
    }

    @Test("일정이 많으면 긴 공휴일을 한 줄로 압축해 일반 일정을 하나 더 표시한다")
    func denseDayCompressesHolidayAndShowsOneMoreEvent() throws {
        let thursday = week.dates[4]
        let holidays: [Date: [Holiday]] = [
            calendar.startOfDay(for: thursday): [
                Holiday(date: thursday, name: "크리스마스", isHoliday: true)
            ]
        ]
        let events = [
            timedOccurrence(id: "a", title: "아침", dayOffset: 4, startHour: 8, endHour: 9),
            timedOccurrence(id: "b", title: "점심", dayOffset: 4, startHour: 12, endHour: 13),
            timedOccurrence(id: "c", title: "저녁", dayOffset: 4, startHour: 18, endHour: 19)
        ]
        let result = layout(
            occurrences: events,
            holidaysByDate: holidays,
            holidayTextWidth: 48
        )
        let firstEventY = try #require(result.visibleSegments.map(\.yOffset).min())
        let compressedHolidayBottom = CalendarDayContentLayout.dateHeaderHeight
            + CalendarDayContentLayout.holidayLineHeight

        #expect(result.holidayLineCounts[4] == 1)
        #expect(result.visibleSegments.count == 3)
        #expect(result.overflowCounts[4] == nil)
        #expect(firstEventY >= compressedHolidayBottom + CalendarDayContentLayout.contentSpacing)
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

@Suite("DDayCalculator")
struct DDayCalculatorTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("10일 남았으면 daysRemaining이 10이다")
    func tenDaysRemaining() {
        let now = date(year: 2026, month: 1, day: 1)
        let target = date(year: 2026, month: 1, day: 11)
        #expect(DDayCalculator.daysRemaining(until: target, now: now, calendar: calendar) == 10)
    }

    @Test("당일(같은 날짜)이면 시각과 무관하게 0이다")
    func sameDayIsZeroRegardlessOfTime() {
        let now = date(year: 2026, month: 1, day: 1, hour: 23)
        let target = date(year: 2026, month: 1, day: 1, hour: 1)
        #expect(DDayCalculator.daysRemaining(until: target, now: now, calendar: calendar) == 0)
        #expect(DDayCalculator.displayText(forDaysRemaining: 0) == String(localized: "D-Day"))
    }

    @Test("지난 날짜는 음수이고 isPast가 true다")
    func pastDateIsNegativeAndIsPast() {
        let now = date(year: 2026, month: 1, day: 10)
        let target = date(year: 2026, month: 1, day: 1)
        let days = DDayCalculator.daysRemaining(until: target, now: now, calendar: calendar)
        #expect(days == -9)
        #expect(DDayCalculator.isPast(targetDate: target, now: now, calendar: calendar))
    }

    @Test("연도 경계를 넘어가도 정확히 계산된다(2025-12-28 → 2026-01-02)")
    func crossesYearBoundary() {
        let now = date(year: 2025, month: 12, day: 28)
        let target = date(year: 2026, month: 1, day: 2)
        #expect(DDayCalculator.daysRemaining(until: target, now: now, calendar: calendar) == 5)
    }

    @Test("윤년 2월 29일을 정확히 지나 계산된다(2024-02-27 → 2024-03-01)")
    func crossesLeapDay() {
        let now = date(year: 2024, month: 2, day: 27)
        let target = date(year: 2024, month: 3, day: 1)
        #expect(DDayCalculator.daysRemaining(until: target, now: now, calendar: calendar) == 3)
    }

    @Test("월말 경계를 정확히 넘어간다(1월 31일 → 2월 1일)")
    func crossesMonthEnd() {
        let now = date(year: 2026, month: 1, day: 31)
        let target = date(year: 2026, month: 2, day: 1)
        #expect(DDayCalculator.daysRemaining(until: target, now: now, calendar: calendar) == 1)
    }

    @Test("표시 문자열은 양수일 때 D-N, 0 이하일 때 D-Day다")
    func displayTextFormat() {
        #expect(DDayCalculator.displayText(forDaysRemaining: 10) == "D-10")
        #expect(DDayCalculator.displayText(forDaysRemaining: 1) == "D-1")
        #expect(DDayCalculator.displayText(forDaysRemaining: 0) == String(localized: "D-Day"))
    }
}

@Suite("SystemCalendarEventReference D-Day 시리즈 매칭 (Step 5-2 반복 보완)")
struct SystemCalendarEventReferenceDDayMatchingTests {
    private func reference(
        eventIdentifier: String? = "event-1",
        calendarItemIdentifier: String = "item-1",
        externalIdentifier: String? = nil,
        startDate: Date = Date(),
        occurrenceDate: Date? = nil,
        isRecurring: Bool = false
    ) -> SystemCalendarEventReference {
        SystemCalendarEventReference(
            eventIdentifier: eventIdentifier,
            calendarItemIdentifier: calendarItemIdentifier,
            externalIdentifier: externalIdentifier,
            calendarIdentifier: "cal-1",
            startDate: startDate,
            occurrenceDate: occurrenceDate,
            isRecurring: isRecurring
        )
    }

    @Test("반복이 아닌 일정은 eventIdentifier만 같아도 같은 시리즈로 본다")
    func nonRecurringMatchesByEventIdentifier() {
        let a = reference(eventIdentifier: "same", startDate: Date())
        let b = reference(eventIdentifier: "same", startDate: Date().addingTimeInterval(3_600))
        #expect(a.matchesSeries(of: b))
    }

    @Test("eventIdentifier가 없으면 calendarItemIdentifier로 같은 시리즈인지 판단한다")
    func fallsBackToCalendarItemIdentifier() {
        let a = reference(eventIdentifier: nil, calendarItemIdentifier: "item-x")
        let b = reference(eventIdentifier: nil, calendarItemIdentifier: "item-x")
        #expect(a.matchesSeries(of: b))
    }

    @Test("식별자가 모두 다르면 같은 시리즈가 아니다")
    func differentIdentifiersAreNotSameSeries() {
        let a = reference(eventIdentifier: "a", calendarItemIdentifier: "item-a")
        let b = reference(eventIdentifier: "b", calendarItemIdentifier: "item-b")
        #expect(!a.matchesSeries(of: b))
    }

    @Test("확정된 반복 정책: 같은 시리즈면 발생 시각이 달라도(서로 다른 회차) 같은 시리즈로 본다")
    func recurringSeriesMatchesRegardlessOfOccurrenceDate() {
        let day1 = Date()
        let day2 = Date().addingTimeInterval(86_400 * 7)
        let a = reference(calendarItemIdentifier: "series-1", startDate: day1, isRecurring: true)
        let b = reference(calendarItemIdentifier: "series-1", startDate: day2, isRecurring: true)
        // Step 5-2 반복 보완: D-Day는 발생분이 아니라 시리즈 전체에 적용된다.
        #expect(a.matchesSeries(of: b))
    }

    @Test("모든 식별자가 다르면 occurrenceDate가 우연히 같아도 다른 시리즈로 본다(매칭은 식별자만 본다)")
    func differentSeriesWithSameOccurrenceDateAreNotConfused() {
        let occurrence = Date()
        let a = reference(
            eventIdentifier: "event-a", calendarItemIdentifier: "series-1",
            occurrenceDate: occurrence, isRecurring: true
        )
        let b = reference(
            eventIdentifier: "event-b", calendarItemIdentifier: "series-2",
            occurrenceDate: occurrence, isRecurring: true
        )
        #expect(!a.matchesSeries(of: b))
    }
}

@Suite("EventOccurrenceService.nextOccurrenceDate (Step 5-2 반복 보완)")
struct NextOccurrenceDateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func date(year: Int, month: Int, day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("반복하지 않는 일정은 nil을 반환한다(호출하는 쪽에서 시작일을 그대로 쓴다)")
    func nonRepeatingReturnsNil() {
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2020, month: 1, day: 1),
            repeatUnit: "반복 안 함",
            repeatInterval: 1,
            onOrAfter: date(year: 2026, month: 1, day: 1),
            calendar: calendar
        )
        #expect(result == nil)
    }

    @Test("매년 반복되는 생일: 생일 전날은 올해 생일이 다음 발생일이다")
    func yearlyBirthdayDayBefore() {
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2020, month: 10, day: 20),
            repeatUnit: "년",
            repeatInterval: 1,
            onOrAfter: date(year: 2026, month: 10, day: 19),
            calendar: calendar
        )
        let expected = date(year: 2026, month: 10, day: 20)
        #expect(result.map { calendar.isDate($0, inSameDayAs: expected) } == true)
    }

    @Test("매년 반복되는 생일: 당일은 당일 자신이 다음 발생일이다(D-Day)")
    func yearlyBirthdayOnTheDay() {
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2020, month: 10, day: 20),
            repeatUnit: "년",
            repeatInterval: 1,
            onOrAfter: date(year: 2026, month: 10, day: 20),
            calendar: calendar
        )
        let expected = date(year: 2026, month: 10, day: 20)
        #expect(result.map { calendar.isDate($0, inSameDayAs: expected) } == true)
    }

    @Test("매년 반복되는 생일: 생일 다음 날은 내년 생일이 다음 발생일이다")
    func yearlyBirthdayDayAfterRollsToNextYear() {
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2020, month: 10, day: 20),
            repeatUnit: "년",
            repeatInterval: 1,
            onOrAfter: date(year: 2026, month: 10, day: 21),
            calendar: calendar
        )
        let expected = date(year: 2027, month: 10, day: 20)
        #expect(result.map { calendar.isDate($0, inSameDayAs: expected) } == true)
    }

    @Test("매일 반복: 오늘도 다음 발생일로 포함된다")
    func dailyIncludesToday() {
        let today = date(year: 2026, month: 3, day: 15)
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2026, month: 1, day: 1),
            repeatUnit: "일",
            repeatInterval: 1,
            onOrAfter: today,
            calendar: calendar
        )
        #expect(result.map { calendar.isDate($0, inSameDayAs: today) } == true)
    }

    @Test("매주 반복: 시작일보다 과거에서 조회해도 과거 시작일 자체를 반환한다")
    func weeklyFromThePast() {
        let start = date(year: 2026, month: 6, day: 1)
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: start,
            repeatUnit: "주",
            repeatInterval: 1,
            onOrAfter: date(year: 2020, month: 1, day: 1),
            calendar: calendar
        )
        #expect(result.map { calendar.isDate($0, inSameDayAs: start) } == true)
    }

    @Test("매월 반복: 월말(31일) 기준 반복은 31일이 없는 달을 건너뛰고 다음 31일을 찾는다")
    func monthlyOnThirtyFirstSkipsShorterMonths() {
        // 4월은 30일까지라 31일이 없다 — 기존 월간 반복 규칙(validatedDate)이 건너뛴다.
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2026, month: 1, day: 31),
            repeatUnit: "개월",
            repeatInterval: 1,
            onOrAfter: date(year: 2026, month: 4, day: 1),
            calendar: calendar
        )
        let expected = date(year: 2026, month: 5, day: 31)
        #expect(result.map { calendar.isDate($0, inSameDayAs: expected) } == true)
    }

    @Test("윤년 2월 29일 매년 반복: 평년에는 건너뛰고 다음 2월 29일(윤년)을 찾는다")
    func yearlyOnLeapDaySkipsNonLeapYears() {
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2024, month: 2, day: 29),
            repeatUnit: "년",
            repeatInterval: 1,
            onOrAfter: date(year: 2025, month: 1, day: 1),
            calendar: calendar
        )
        let expected = date(year: 2028, month: 2, day: 29)
        #expect(result.map { calendar.isDate($0, inSameDayAs: expected) } == true)
    }

    @Test("연도 경계: 12월 반복 일정이 다음 해 1월로 자연스럽게 넘어간다")
    func crossesYearBoundary() {
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2025, month: 12, day: 31),
            repeatUnit: "개월",
            repeatInterval: 1,
            onOrAfter: date(year: 2026, month: 1, day: 1),
            calendar: calendar
        )
        // 1월엔 31일이 있으므로(건너뛰지 않음) 1월 31일이 다음 발생일이다.
        let expected = date(year: 2026, month: 1, day: 31)
        #expect(result.map { calendar.isDate($0, inSameDayAs: expected) } == true)
    }
}

@MainActor
@Suite("ExternalDDayStore 레거시 발생분 단위 데이터 호환 (Step 5-2 반복 보완)")
struct ExternalDDayStoreLegacyCompatibilityTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ExternalEventDDaySetting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func reference(
        calendarItemIdentifier: String = "series-1",
        startDate: Date = Date(),
        isRecurring: Bool = true
    ) -> SystemCalendarEventReference {
        SystemCalendarEventReference(
            eventIdentifier: "event-1",
            calendarItemIdentifier: calendarItemIdentifier,
            externalIdentifier: nil,
            calendarIdentifier: "cal-1",
            startDate: startDate,
            occurrenceDate: nil,
            isRecurring: isRecurring
        )
    }

    @Test("과거 발생분 단위로 저장된 레코드가 여러 개 있어도, 하나라도 켜져 있으면 켜진 것으로 본다")
    func anyEnabledLegacyRecordCountsAsEnabled() throws {
        let context = try makeContext()
        // 과거 정책(발생분 단위)으로 저장됐다고 가정한 두 레코드: 같은 시리즈, 다른 발생 시각, 다른 켬끔 값.
        let off = ExternalEventDDaySetting(
            eventIdentifier: "event-1", calendarItemIdentifier: "series-1", externalIdentifier: nil,
            calendarIdentifier: "cal-1", occurrenceStartDate: Date(), occurrenceDate: nil,
            isRecurring: true, isEnabled: false
        )
        let on = ExternalEventDDaySetting(
            eventIdentifier: "event-1", calendarItemIdentifier: "series-1", externalIdentifier: nil,
            calendarIdentifier: "cal-1", occurrenceStartDate: Date().addingTimeInterval(86_400 * 30), occurrenceDate: nil,
            isRecurring: true, isEnabled: true
        )
        context.insert(off)
        context.insert(on)
        try context.save()

        let settings = try context.fetch(FetchDescriptor<ExternalEventDDaySetting>())
        #expect(ExternalDDayStore.isEnabled(for: reference(), in: settings))
    }

    @Test("켬끔을 저장하면 같은 시리즈의 기존 레코드를 모두 같은 값으로 맞춘다(삭제하지 않는다)")
    func setEnabledUpdatesAllMatchingLegacyRecordsWithoutDeleting() throws {
        let context = try makeContext()
        let first = ExternalEventDDaySetting(
            eventIdentifier: "event-1", calendarItemIdentifier: "series-1", externalIdentifier: nil,
            calendarIdentifier: "cal-1", occurrenceStartDate: Date(), occurrenceDate: nil,
            isRecurring: true, isEnabled: true
        )
        let second = ExternalEventDDaySetting(
            eventIdentifier: "event-1", calendarItemIdentifier: "series-1", externalIdentifier: nil,
            calendarIdentifier: "cal-1", occurrenceStartDate: Date().addingTimeInterval(86_400 * 30), occurrenceDate: nil,
            isRecurring: true, isEnabled: true
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let settings = try context.fetch(FetchDescriptor<ExternalEventDDaySetting>())
        ExternalDDayStore.setEnabled(false, for: reference(), existingSettings: settings, context: context)

        #expect(settings.allSatisfy { !$0.isEnabled })
        // 레코드를 지우지 않고 값만 맞췄는지 확인한다(기존 데이터 삭제 금지 원칙).
        let afterCount = try context.fetch(FetchDescriptor<ExternalEventDDaySetting>()).count
        #expect(afterCount == 2)
    }

    @Test("매칭되는 설정이 없으면 정확히 하나만 새로 만든다(중복 생성 방지)")
    func setEnabledCreatesExactlyOneWhenNoneExist() throws {
        let context = try makeContext()
        let created = ExternalDDayStore.setEnabled(true, for: reference(), existingSettings: [], context: context)
        try context.save()

        #expect(created.isEnabled)
        let all = try context.fetch(FetchDescriptor<ExternalEventDDaySetting>())
        #expect(all.count == 1)
    }

    @Test("반복 시리즈의 다른 발생분(발생 시각만 다름)도 같은 설정으로 매칭된다")
    func matchesAcrossDifferentOccurrencesOfSameSeries() throws {
        let context = try makeContext()
        let setting = ExternalDDayStore.setEnabled(
            true,
            for: reference(startDate: Date()),
            existingSettings: [],
            context: context
        )
        try context.save()

        let laterOccurrence = reference(startDate: Date().addingTimeInterval(86_400 * 365))
        let settings = try context.fetch(FetchDescriptor<ExternalEventDDaySetting>())
        #expect(ExternalDDayStore.isEnabled(for: laterOccurrence, in: settings))
        #expect(settings.first?.id == setting.id)
    }
}

@MainActor
@Suite("DDayWidgetSource.bestMatchingOccurrences — 외부 반복 시리즈 매칭·중복 제거 (Step 5-2 최종 보완)")
struct DDayWidgetSourceMatchingTests {
    private func reference(
        eventIdentifier: String?,
        calendarItemIdentifier: String,
        startDate: Date,
        isRecurring: Bool = true
    ) -> SystemCalendarEventReference {
        SystemCalendarEventReference(
            eventIdentifier: eventIdentifier,
            calendarItemIdentifier: calendarItemIdentifier,
            externalIdentifier: nil,
            calendarIdentifier: "cal-1",
            startDate: startDate,
            occurrenceDate: startDate,
            isRecurring: isRecurring
        )
    }

    private func occurrence(
        title: String,
        startDate: Date,
        reference: SystemCalendarEventReference
    ) -> CalendarDisplayOccurrence {
        CalendarDisplayOccurrence(
            id: "system:\(reference.calendarItemIdentifier):\(startDate.timeIntervalSince1970)",
            source: .system(calendarTitle: "테스트 캘린더", reference: reference),
            title: title,
            isAllDay: false,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600),
            color: .blue
        )
    }

    private func setting(
        eventIdentifier: String?,
        calendarItemIdentifier: String,
        occurrenceStartDate: Date,
        isRecurring: Bool = true,
        isEnabled: Bool = true
    ) -> ExternalEventDDaySetting {
        ExternalEventDDaySetting(
            eventIdentifier: eventIdentifier,
            calendarItemIdentifier: calendarItemIdentifier,
            externalIdentifier: nil,
            calendarIdentifier: "cal-1",
            occurrenceStartDate: occurrenceStartDate,
            occurrenceDate: occurrenceStartDate,
            isRecurring: isRecurring,
            isEnabled: isEnabled
        )
    }

    @Test("같은 반복 시리즈의 여러 발생분 중 가장 이른 것만 남긴다(중복 표시 방지)")
    func keepsOnlyEarliestOccurrencePerSeries() {
        let early = Date()
        let later = Date().addingTimeInterval(86_400 * 365)
        let ref1 = reference(eventIdentifier: "event-1", calendarItemIdentifier: "series-1", startDate: early)
        let ref2 = reference(eventIdentifier: "event-1", calendarItemIdentifier: "series-1", startDate: later)

        let occurrences = [
            occurrence(title: "생일", startDate: later, reference: ref2),
            occurrence(title: "생일", startDate: early, reference: ref1)
        ]
        let settings = [setting(eventIdentifier: "event-1", calendarItemIdentifier: "series-1", occurrenceStartDate: early)]

        let result = DDayWidgetSource.bestMatchingOccurrences(from: occurrences, enabledSettings: settings)

        #expect(result.count == 1)
        #expect(result.first?.startDate == early)
    }

    @Test("서로 다른 두 반복 시리즈가 각각 매칭되고 서로 섞이지 않는다")
    func matchesEachSeriesIndependently() {
        let dateA = Date()
        let dateB = Date().addingTimeInterval(86_400 * 10)
        let refA = reference(eventIdentifier: "event-a", calendarItemIdentifier: "series-a", startDate: dateA)
        let refB = reference(eventIdentifier: "event-b", calendarItemIdentifier: "series-b", startDate: dateB)

        let occurrences = [
            occurrence(title: "생일", startDate: dateA, reference: refA),
            occurrence(title: "기념일", startDate: dateB, reference: refB)
        ]
        let settings = [
            setting(eventIdentifier: "event-a", calendarItemIdentifier: "series-a", occurrenceStartDate: dateA),
            setting(eventIdentifier: "event-b", calendarItemIdentifier: "series-b", occurrenceStartDate: dateB)
        ]

        let result = DDayWidgetSource.bestMatchingOccurrences(from: occurrences, enabledSettings: settings)

        #expect(result.count == 2)
        #expect(Set(result.map(\.title)) == Set(["생일", "기념일"]))
    }

    @Test("켜진 설정에 매칭되지 않는 발생분(D-Day 꺼짐·무관한 일정)은 제외된다")
    func excludesOccurrencesNotMatchingAnyEnabledSetting() {
        let date = Date()
        let matchingRef = reference(eventIdentifier: "event-1", calendarItemIdentifier: "series-1", startDate: date)
        let unrelatedRef = reference(eventIdentifier: "event-2", calendarItemIdentifier: "series-2", startDate: date)

        let occurrences = [
            occurrence(title: "D-Day 켜짐", startDate: date, reference: matchingRef),
            occurrence(title: "D-Day 꺼짐(무관)", startDate: date, reference: unrelatedRef)
        ]
        let settings = [setting(eventIdentifier: "event-1", calendarItemIdentifier: "series-1", occurrenceStartDate: date)]

        let result = DDayWidgetSource.bestMatchingOccurrences(from: occurrences, enabledSettings: settings)

        #expect(result.count == 1)
        #expect(result.first?.title == "D-Day 켜짐")
    }

    @Test("과거 발생분 단위로 중복 저장된 설정 두 개가 있어도 결과는 하나만 나온다")
    func legacyDuplicateSettingsStillProduceSingleResult() {
        let date = Date()
        let ref = reference(eventIdentifier: "event-1", calendarItemIdentifier: "series-1", startDate: date)
        let occurrences = [occurrence(title: "생일", startDate: date, reference: ref)]

        // 과거(발생분 단위) 정책 때 같은 시리즈에 생긴 두 개의 레거시 설정.
        let settings = [
            setting(eventIdentifier: "event-1", calendarItemIdentifier: "series-1", occurrenceStartDate: date),
            setting(eventIdentifier: "event-1", calendarItemIdentifier: "series-1", occurrenceStartDate: date.addingTimeInterval(86_400 * 365))
        ]

        let result = DDayWidgetSource.bestMatchingOccurrences(from: occurrences, enabledSettings: settings)

        #expect(result.count == 1)
    }

    @Test("빈 발생분 목록이면 빈 결과를 반환한다")
    func emptyOccurrencesProduceEmptyResult() {
        let result = DDayWidgetSource.bestMatchingOccurrences(from: [], enabledSettings: [])
        #expect(result.isEmpty)
    }
}

@Suite("반복 종료 날짜 (Step 5-2 실기기 테스트 후 수정)")
struct RepeatEndDateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func date(year: Int, month: Int, day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func yearlyEvent(
        startDate: Date,
        repeatEndDate: Date?
    ) -> Event {
        Event(
            title: "생일",
            isAllDay: false,
            startDate: startDate,
            endDate: startDate,
            color: "blue",
            alarmOption: "없음",
            alarmTimeIntervalBeforeStart: nil,
            alarmCustomValue: 1,
            alarmCustomUnit: "일",
            repeatUnit: "년",
            repeatInterval: 1,
            memo: "",
            repeatEndDate: repeatEndDate
        )
    }

    // MARK: - occurrences(for:intersecting:)

    @Test("반복 종료일 당일 발생분은 포함된다(종료일 포함 규칙)")
    func occurrencesIncludeTheEndDateItself() {
        let start = date(year: 2020, month: 10, day: 20)
        let end = date(year: 2027, month: 10, day: 20)
        let event = yearlyEvent(startDate: start, repeatEndDate: end)

        let range = DateInterval(
            start: date(year: 2027, month: 10, day: 1),
            end: date(year: 2027, month: 10, day: 31)
        )
        let results = EventOccurrenceService.occurrences(for: event, intersecting: range, calendar: calendar)

        #expect(results.count == 1)
        #expect(results.first.map { calendar.isDate($0.startDate, inSameDayAs: end) } == true)
    }

    @Test("반복 종료일 다음 발생분부터는 더 이상 만들어지지 않는다")
    func occurrencesExcludeAnythingAfterTheEndDate() {
        let start = date(year: 2020, month: 10, day: 20)
        let end = date(year: 2027, month: 10, day: 20)
        let event = yearlyEvent(startDate: start, repeatEndDate: end)

        let range = DateInterval(
            start: date(year: 2020, month: 1, day: 1),
            end: date(year: 2030, month: 1, day: 1)
        )
        let results = EventOccurrenceService.occurrences(for: event, intersecting: range, calendar: calendar)

        // 2020~2027년(종료일 당일 포함) 8회만 있어야 하고, 2028년 이후는 없어야 한다.
        #expect(results.count == 8)
        #expect(results.allSatisfy { calendar.component(.year, from: $0.startDate) <= 2027 })
    }

    @Test("반복 종료 날짜가 nil이면 기존처럼 무기한 반복된다(회귀 방지)")
    func nilRepeatEndDateStillRepeatsIndefinitely() {
        let start = date(year: 2020, month: 10, day: 20)
        let event = yearlyEvent(startDate: start, repeatEndDate: nil)

        let range = DateInterval(
            start: date(year: 2020, month: 1, day: 1),
            end: date(year: 2030, month: 1, day: 1)
        )
        let results = EventOccurrenceService.occurrences(for: event, intersecting: range, calendar: calendar)

        // 2020~2029년까지 10회 전부 있어야 한다(종료 조건이 없으므로 범위 끝까지 계속 생성).
        #expect(results.count == 10)
    }

    // MARK: - nextOccurrenceDate

    @Test("반복 종료일 이전에 조회하면 평소대로 다음 발생일을 반환한다")
    func nextOccurrenceDateBeforeEndDateWorksNormally() {
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2020, month: 10, day: 20),
            repeatUnit: "년",
            repeatInterval: 1,
            onOrAfter: date(year: 2026, month: 10, day: 19),
            calendar: calendar,
            repeatEndDate: date(year: 2030, month: 10, day: 20)
        )
        let expected = date(year: 2026, month: 10, day: 20)
        #expect(result.map { calendar.isDate($0, inSameDayAs: expected) } == true)
    }

    @Test("종료일 당일을 조회 기준으로 쓰면 종료일 당일 발생분을 반환한다(종료일 포함)")
    func nextOccurrenceDateOnTheEndDateItselfIsIncluded() {
        let end = date(year: 2027, month: 10, day: 20)
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2020, month: 10, day: 20),
            repeatUnit: "년",
            repeatInterval: 1,
            onOrAfter: end,
            calendar: calendar,
            repeatEndDate: end
        )
        #expect(result.map { calendar.isDate($0, inSameDayAs: end) } == true)
    }

    @Test("반복 종료일을 지난 뒤에 조회하면 nil을 반환한다(반복이 끝남)")
    func nextOccurrenceDateAfterEndDateReturnsNil() {
        let end = date(year: 2027, month: 10, day: 20)
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2020, month: 10, day: 20),
            repeatUnit: "년",
            repeatInterval: 1,
            onOrAfter: date(year: 2027, month: 10, day: 21),
            calendar: calendar,
            repeatEndDate: end
        )
        #expect(result == nil)
    }

    @Test("repeatEndDate를 생략하면(기본값 nil) 기존 동작과 동일하게 무기한 탐색한다(회귀 방지)")
    func omittingRepeatEndDateDefaultsToUnbounded() {
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: date(year: 2020, month: 10, day: 20),
            repeatUnit: "년",
            repeatInterval: 1,
            onOrAfter: date(year: 2040, month: 10, day: 21),
            calendar: calendar
        )
        let expected = date(year: 2041, month: 10, day: 20)
        #expect(result.map { calendar.isDate($0, inSameDayAs: expected) } == true)
    }

    @Test("Event 기반 편의 오버로드는 event.repeatEndDate를 그대로 반영한다")
    func eventConvenienceOverloadUsesEventRepeatEndDate() {
        let end = date(year: 2027, month: 10, day: 20)
        let event = yearlyEvent(startDate: date(year: 2020, month: 10, day: 20), repeatEndDate: end)

        let beforeEnd = EventOccurrenceService.nextOccurrenceDate(
            for: event,
            onOrAfter: date(year: 2026, month: 10, day: 19),
            calendar: calendar
        )
        #expect(beforeEnd.map { calendar.isDate($0, inSameDayAs: date(year: 2026, month: 10, day: 20)) } == true)

        let afterEnd = EventOccurrenceService.nextOccurrenceDate(
            for: event,
            onOrAfter: date(year: 2027, month: 10, day: 21),
            calendar: calendar
        )
        #expect(afterEnd == nil)
    }

    @Test("기존 정상 계산 보호: 2026-10-10 생일이 D-Day, 2027-10-10 발생분은 종료일 설정이 없으면 그대로 D-365로 계산된다")
    func protectsKnownGoodUnboundedYearlyCalculation() {
        let start = date(year: 2020, month: 10, day: 10)
        let onDDay = date(year: 2026, month: 10, day: 10)
        let result = EventOccurrenceService.nextOccurrenceDate(
            startDate: start,
            repeatUnit: "년",
            repeatInterval: 1,
            onOrAfter: calendar.date(byAdding: .day, value: 1, to: onDDay)!,
            calendar: calendar,
            repeatEndDate: nil
        )
        let expectedNext = date(year: 2027, month: 10, day: 10)
        #expect(result.map { calendar.isDate($0, inSameDayAs: expectedNext) } == true)
        let days = DDayCalculator.daysRemaining(until: expectedNext, now: onDDay, calendar: calendar)
        #expect(days == 365)
    }
}

@Suite("반복 일정 개별 수정·삭제 예외 (Step 5-2 실기기 테스트 후 수정)")
struct EventOccurrenceExceptionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func date(year: Int, month: Int, day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// 명세 예시 그대로: 매주 월요일 오전 10시 운동(2026-10-05부터).
    private func weeklyWorkoutEvent() -> Event {
        Event(
            title: "운동",
            isAllDay: false,
            startDate: date(year: 2026, month: 10, day: 5),
            endDate: date(year: 2026, month: 10, day: 5, hour: 11),
            color: "파란색",
            alarmOption: "없음",
            alarmTimeIntervalBeforeStart: nil,
            alarmCustomValue: 1,
            alarmCustomUnit: "일",
            repeatUnit: "주",
            repeatInterval: 1,
            memo: ""
        )
    }

    private func exclusion(for event: Event, originalStart: Date) -> EventOccurrenceException {
        EventOccurrenceException(
            eventID: event.id,
            originalOccurrenceStartDate: originalStart,
            isExcluded: true
        )
    }

    private func override(
        for event: Event,
        originalStart: Date,
        newTitle: String,
        newStart: Date,
        newEnd: Date
    ) -> EventOccurrenceException {
        EventOccurrenceException(
            eventID: event.id,
            originalOccurrenceStartDate: originalStart,
            isExcluded: false,
            overrideTitle: newTitle,
            overrideStartDate: newStart,
            overrideEndDate: newEnd
        )
    }

    private func seriesValues(
        for event: Event,
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        color: String? = nil,
        repeatUnit: String? = nil,
        repeatInterval: Int? = nil,
        memo: String? = nil
    ) -> RecurringSeriesValues {
        RecurringSeriesValues(
            title: title ?? event.title,
            isAllDay: event.isAllDay,
            startDate: startDate ?? event.startDate,
            endDate: endDate ?? event.endDate,
            color: color ?? event.color,
            alarmOption: event.alarmOption,
            alarmTimeIntervalBeforeStart: event.alarmTimeIntervalBeforeStart,
            alarmCustomValue: event.alarmCustomValue,
            alarmCustomUnit: event.alarmCustomUnit,
            repeatUnit: repeatUnit ?? event.repeatUnit,
            repeatInterval: repeatInterval ?? event.repeatInterval,
            memo: memo ?? event.memo
        )
    }

    @Test("명세 예시: 10월 19일 발생분만 11시로 옮기면 그 발생분만 바뀌고 나머지는 그대로다")
    func singleOccurrenceOverrideShiftsOnlyThatDate() {
        let event = weeklyWorkoutEvent()
        let originalOct19 = date(year: 2026, month: 10, day: 19) // 10시
        let movedOct19 = date(year: 2026, month: 10, day: 19, hour: 11)
        let exception = override(
            for: event,
            originalStart: originalOct19,
            newTitle: "운동",
            newStart: movedOct19,
            newEnd: movedOct19.addingTimeInterval(3_600)
        )

        let range = DateInterval(
            start: date(year: 2026, month: 10, day: 1),
            end: date(year: 2026, month: 11, day: 1)
        )
        let results = EventOccurrenceService.occurrences(
            for: event, intersecting: range, calendar: calendar, exceptions: [exception]
        )

        let oct12 = results.first { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 12)) }
        let oct19 = results.first { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 19)) }
        let oct26 = results.first { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 26)) }

        #expect(calendar.component(.hour, from: oct12?.startDate ?? .distantPast) == 10)
        #expect(calendar.component(.hour, from: oct19?.startDate ?? .distantPast) == 11)
        #expect(calendar.component(.hour, from: oct26?.startDate ?? .distantPast) == 10)
        // 옮긴 발생분이 원래 슬롯(10시)에 중복으로 남지 않아야 한다.
        #expect(results.filter { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 19)) }.count == 1)
    }

    @Test("명세 예시: 10월 19일 발생분만 삭제하면 그 날짜만 빠지고 나머지는 그대로 표시된다")
    func singleOccurrenceExclusionRemovesOnlyThatDate() {
        let event = weeklyWorkoutEvent()
        let originalOct19 = date(year: 2026, month: 10, day: 19)
        let exception = exclusion(for: event, originalStart: originalOct19)

        let range = DateInterval(
            start: date(year: 2026, month: 10, day: 1),
            end: date(year: 2026, month: 11, day: 1)
        )
        let results = EventOccurrenceService.occurrences(
            for: event, intersecting: range, calendar: calendar, exceptions: [exception]
        )

        #expect(results.contains { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 12)) })
        #expect(!results.contains { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 19)) })
        #expect(results.contains { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 26)) })
    }

    @Test("override된 발생분은 title·colorName도 함께 바뀐다")
    func overrideAppliesToTitleAndColor() {
        let event = weeklyWorkoutEvent()
        let originalOct19 = date(year: 2026, month: 10, day: 19)
        let exception = EventOccurrenceException(
            eventID: event.id,
            originalOccurrenceStartDate: originalOct19,
            isExcluded: false,
            overrideTitle: "헬스장 변경",
            overrideStartDate: originalOct19,
            overrideEndDate: originalOct19.addingTimeInterval(3_600),
            overrideColor: "빨간색"
        )

        let range = DateInterval(
            start: date(year: 2026, month: 10, day: 1),
            end: date(year: 2026, month: 11, day: 1)
        )
        let results = EventOccurrenceService.occurrences(
            for: event, intersecting: range, calendar: calendar, exceptions: [exception]
        )

        let oct19 = results.first { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 19)) }
        let oct12 = results.first { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 12)) }

        #expect(oct19?.title == "헬스장 변경")
        #expect(oct19?.colorName == "빨간색")
        #expect(oct12?.title == "운동")
        #expect(oct12?.colorName == "파란색")
    }

    @Test("nextOccurrenceDate는 가까운 미래의 override된 발생분을 그 새 시각 그대로 다음 발생일로 찾는다")
    func nextOccurrenceDateReflectsOverride() {
        let event = weeklyWorkoutEvent()
        let originalOct19 = date(year: 2026, month: 10, day: 19)
        let movedOct19 = date(year: 2026, month: 10, day: 19, hour: 11)
        let exception = override(
            for: event,
            originalStart: originalOct19,
            newTitle: "운동",
            newStart: movedOct19,
            newEnd: movedOct19.addingTimeInterval(3_600)
        )

        let result = EventOccurrenceService.nextOccurrenceDate(
            for: event,
            onOrAfter: date(year: 2026, month: 10, day: 19),
            calendar: calendar,
            exceptions: [exception]
        )

        #expect(result == movedOct19)
    }

    @Test("nextOccurrenceDate는 개별 삭제된 발생분을 건너뛰고 그다음 유효한 발생분을 찾는다")
    func nextOccurrenceDateSkipsExcludedOccurrence() {
        let event = weeklyWorkoutEvent()
        let originalOct19 = date(year: 2026, month: 10, day: 19)
        let exception = exclusion(for: event, originalStart: originalOct19)

        let result = EventOccurrenceService.nextOccurrenceDate(
            for: event,
            onOrAfter: date(year: 2026, month: 10, day: 19),
            calendar: calendar,
            exceptions: [exception]
        )

        let expected = date(year: 2026, month: 10, day: 26)
        #expect(result.map { calendar.isDate($0, inSameDayAs: expected) } == true)
    }

    @Test("다른 일정의 예외는 섞이지 않는다(events 배열 기준 eventID별로 올바르게 그룹핑된다)")
    func exceptionsAreScopedToTheirOwnEvent() {
        let eventA = weeklyWorkoutEvent()
        let eventB = weeklyWorkoutEvent()
        let originalOct19 = date(year: 2026, month: 10, day: 19)
        // eventB의 10/19만 삭제 — eventA에는 영향이 없어야 한다.
        let exceptionForB = exclusion(for: eventB, originalStart: originalOct19)

        let range = DateInterval(
            start: date(year: 2026, month: 10, day: 1),
            end: date(year: 2026, month: 11, day: 1)
        )
        let results = EventOccurrenceService.occurrences(
            for: [eventA, eventB], intersecting: range, calendar: calendar, exceptions: [exceptionForB]
        )

        let eventAOct19Count = results.filter { $0.event.id == eventA.id && calendar.isDate($0.startDate, inSameDayAs: originalOct19) }.count
        let eventBOct19Count = results.filter { $0.event.id == eventB.id && calendar.isDate($0.startDate, inSameDayAs: originalOct19) }.count

        #expect(eventAOct19Count == 1)
        #expect(eventBOct19Count == 0)
    }

    @Test("""
    (수정 전 버그 재현) 예외를 그대로 둔 채 시리즈 시작일만 옮기면, 예외가 가리키던 \
    발생일이 새 반복 시퀀스와 더 이상 맞지 않아 그 발생분이 override되지 않은 채로 돌아온다
    """)
    func exceptionBecomesOrphanedIfNotShiftedWithSeries() {
        let event = weeklyWorkoutEvent()
        let originalOct19 = date(year: 2026, month: 10, day: 19)
        let exception = override(
            for: event,
            originalStart: originalOct19,
            newTitle: "헬스장 변경",
            newStart: date(year: 2026, month: 10, day: 19, hour: 11),
            newEnd: date(year: 2026, month: 10, day: 19, hour: 12)
        )

        // 시리즈 전체를 하루 뒤로 옮긴다(전체 반복 일정 수정, 예외는 손대지 않은 "버그" 상태 시뮬레이션).
        event.startDate = event.startDate.addingTimeInterval(86_400)
        event.endDate = event.endDate.addingTimeInterval(86_400)

        let range = DateInterval(
            start: date(year: 2026, month: 10, day: 1),
            end: date(year: 2026, month: 11, day: 1)
        )
        let results = EventOccurrenceService.occurrences(
            for: event, intersecting: range, calendar: calendar, exceptions: [exception]
        )

        // 새 시퀀스의 10/20 발생분은 더 이상 예외와 매칭되지 않아 override되지 않은 원본 그대로다.
        let oct20 = results.first { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 20)) }
        #expect(oct20?.title == "운동")
        #expect(oct20?.exception == nil)
    }

    @Test("(수정 후 정상 동작) 시리즈 시작일을 옮길 때 예외도 같은 만큼 옮기면 계속 올바른 발생분을 가리킨다")
    func exceptionStaysMatchedWhenShiftedWithSeries() {
        let event = weeklyWorkoutEvent()
        let originalOct19 = date(year: 2026, month: 10, day: 19)
        let exception = override(
            for: event,
            originalStart: originalOct19,
            newTitle: "헬스장 변경",
            newStart: date(year: 2026, month: 10, day: 19, hour: 11),
            newEnd: date(year: 2026, month: 10, day: 19, hour: 12)
        )

        // EventEditorView.update(_:)의 shiftExceptions(for:startDelta:endDelta:)와 같은 보정.
        let delta: TimeInterval = 86_400
        event.startDate = event.startDate.addingTimeInterval(delta)
        event.endDate = event.endDate.addingTimeInterval(delta)
        exception.originalOccurrenceStartDate = exception.originalOccurrenceStartDate.addingTimeInterval(delta)
        exception.overrideStartDate = exception.overrideStartDate.addingTimeInterval(delta)
        exception.overrideEndDate = exception.overrideEndDate.addingTimeInterval(delta)

        let range = DateInterval(
            start: date(year: 2026, month: 10, day: 1),
            end: date(year: 2026, month: 11, day: 1)
        )
        let results = EventOccurrenceService.occurrences(
            for: event, intersecting: range, calendar: calendar, exceptions: [exception]
        )

        let oct20 = results.first { calendar.isDate($0.startDate, inSameDayAs: date(year: 2026, month: 10, day: 20)) }
        #expect(oct20?.title == "헬스장 변경")
        #expect(calendar.component(.hour, from: oct20?.startDate ?? .distantPast) == 11)
    }

    @Test("예외가 전혀 없으면 기존 동작과 동일하다(회귀 방지)")
    func noExceptionsBehavesLikeBefore() {
        let event = weeklyWorkoutEvent()
        let range = DateInterval(
            start: date(year: 2026, month: 10, day: 1),
            end: date(year: 2026, month: 11, day: 1)
        )
        let results = EventOccurrenceService.occurrences(
            for: event, intersecting: range, calendar: calendar
        )

        #expect(results.count == 4) // 10/5, 12, 19, 26
        #expect(results.allSatisfy { $0.exception == nil })
    }

    @Test("개별 예외가 없으면 처리 방법을 묻지 않고 바로 저장한다")
    func noExceptionsSaveDirectly() {
        let event = weeklyWorkoutEvent()
        let requirement = RecurringSeriesExceptionUpdater.saveRequirement(
            exceptions: [],
            oldValues: RecurringSeriesValues(event: event),
            newValues: seriesValues(for: event, title: "새 운동")
        )

        #expect(requirement == .saveDirectly)
    }

    @Test("개별 수정 예외가 있으면 전체 저장 전에 처리 방법 선택이 필요하다")
    func modifiedExceptionRequiresPolicyChoice() {
        let event = weeklyWorkoutEvent()
        let exception = override(
            for: event,
            originalStart: date(year: 2026, month: 10, day: 19),
            newTitle: "개별 운동",
            newStart: date(year: 2026, month: 10, day: 19, hour: 11),
            newEnd: date(year: 2026, month: 10, day: 19, hour: 12)
        )

        let requirement = RecurringSeriesExceptionUpdater.saveRequirement(
            exceptions: [exception],
            oldValues: RecurringSeriesValues(event: event),
            newValues: seriesValues(for: event, title: "새 운동")
        )

        #expect(requirement == .chooseUpdatePolicy)
    }

    @Test("삭제 예외만 있으면 처리 선택창 없이 저장하며 삭제 상태를 유지한다")
    func exclusionOnlySavesWithoutChoice() {
        let event = weeklyWorkoutEvent()
        let exception = exclusion(
            for: event,
            originalStart: date(year: 2026, month: 10, day: 19)
        )

        let requirement = RecurringSeriesExceptionUpdater.saveRequirement(
            exceptions: [exception],
            oldValues: RecurringSeriesValues(event: event),
            newValues: seriesValues(for: event, title: "새 운동")
        )

        #expect(requirement == .saveDirectly)
        #expect(exception.isExcluded)
    }

    @Test("A 선택은 개별 수정 값을 보존하고 수정하지 않은 필드만 새 시리즈 값을 따른다")
    func preservingIndividualChangesMergesOnlyUnmodifiedFields() {
        let event = weeklyWorkoutEvent()
        let original = date(year: 2026, month: 10, day: 19)
        let exception = EventOccurrenceException(
            eventID: event.id,
            originalOccurrenceStartDate: original,
            isExcluded: false,
            overrideTitle: "개별 운동",
            overrideIsAllDay: event.isAllDay,
            overrideStartDate: date(year: 2026, month: 10, day: 19, hour: 11),
            overrideEndDate: date(year: 2026, month: 10, day: 19, hour: 12),
            overrideColor: event.color,
            overrideAlarmOption: event.alarmOption,
            overrideAlarmTimeIntervalBeforeStart: event.alarmTimeIntervalBeforeStart,
            overrideAlarmCustomValue: event.alarmCustomValue,
            overrideAlarmCustomUnit: event.alarmCustomUnit,
            overrideMemo: event.memo
        )

        RecurringSeriesExceptionUpdater.apply(
            from: RecurringSeriesValues(event: event),
            to: seriesValues(for: event, title: "전체 운동", color: "빨간색", memo: "전체 메모"),
            policy: .preserveIndividualChanges,
            exceptions: [exception]
        )

        #expect(exception.overrideTitle == "개별 운동")
        #expect(exception.overrideColor == "빨간색")
        #expect(exception.overrideMemo == "전체 메모")
        #expect(calendar.component(.hour, from: exception.overrideStartDate) == 11)
    }

    @Test("B 선택은 전체에서 변경한 제목을 개별 수정에도 적용하되 변경하지 않은 시간은 유지한다")
    func applyingSeriesChangesUpdatesOnlyChangedFields() {
        let event = weeklyWorkoutEvent()
        let original = date(year: 2026, month: 10, day: 19)
        let exception = override(
            for: event,
            originalStart: original,
            newTitle: "개별 운동",
            newStart: date(year: 2026, month: 10, day: 19, hour: 11),
            newEnd: date(year: 2026, month: 10, day: 19, hour: 12)
        )

        RecurringSeriesExceptionUpdater.apply(
            from: RecurringSeriesValues(event: event),
            to: seriesValues(for: event, title: "전체 운동"),
            policy: .applyChangedSeriesValues,
            exceptions: [exception]
        )

        #expect(exception.overrideTitle == "전체 운동")
        #expect(exception.overrideStartDate == date(year: 2026, month: 10, day: 19, hour: 11))
        #expect(exception.overrideEndDate == date(year: 2026, month: 10, day: 19, hour: 12))
    }

    @Test("개별 삭제는 A와 B 모두 복원하지 않고 시리즈 이동에 맞춰 삭제 슬롯만 이동한다")
    func exclusionsRemainExcludedForBothPolicies() {
        let event = weeklyWorkoutEvent()
        let oldValues = RecurringSeriesValues(event: event)
        let movedStart = calendar.date(byAdding: .day, value: 1, to: event.startDate)!
        let movedEnd = calendar.date(byAdding: .day, value: 1, to: event.endDate)!
        let newValues = seriesValues(for: event, startDate: movedStart, endDate: movedEnd)
        let original = date(year: 2026, month: 10, day: 19)
        let preserveExclusion = exclusion(for: event, originalStart: original)
        let applyExclusion = exclusion(for: event, originalStart: original)

        RecurringSeriesExceptionUpdater.apply(
            from: oldValues,
            to: newValues,
            policy: .preserveIndividualChanges,
            exceptions: [preserveExclusion]
        )
        RecurringSeriesExceptionUpdater.apply(
            from: oldValues,
            to: newValues,
            policy: .applyChangedSeriesValues,
            exceptions: [applyExclusion]
        )

        let expectedSlot = date(year: 2026, month: 10, day: 20)
        #expect(preserveExclusion.isExcluded)
        #expect(applyExclusion.isExcluded)
        #expect(preserveExclusion.originalOccurrenceStartDate == expectedSlot)
        #expect(applyExclusion.originalOccurrenceStartDate == expectedSlot)
    }

    @Test("선택창 표시 여부 판정은 원본 예외를 변경하지 않아 취소해도 데이터가 그대로다")
    func requestingChoiceDoesNotMutateData() {
        let event = weeklyWorkoutEvent()
        let exception = override(
            for: event,
            originalStart: date(year: 2026, month: 10, day: 19),
            newTitle: "개별 운동",
            newStart: date(year: 2026, month: 10, day: 19, hour: 11),
            newEnd: date(year: 2026, month: 10, day: 19, hour: 12)
        )
        let titleBefore = exception.overrideTitle
        let startBefore = exception.overrideStartDate

        _ = RecurringSeriesExceptionUpdater.saveRequirement(
            exceptions: [exception],
            oldValues: RecurringSeriesValues(event: event),
            newValues: seriesValues(for: event, title: "전체 운동")
        )

        #expect(exception.overrideTitle == titleBefore)
        #expect(exception.overrideStartDate == startBefore)
        #expect(event.title == "운동")
    }

    @Test("반복 시작일을 옮기면 수정 예외가 같은 발생 순서의 새 슬롯에 계속 연결된다")
    func startDateChangeKeepsExceptionMatched() {
        let event = weeklyWorkoutEvent()
        let exception = override(
            for: event,
            originalStart: date(year: 2026, month: 10, day: 19),
            newTitle: "개별 운동",
            newStart: date(year: 2026, month: 10, day: 19, hour: 11),
            newEnd: date(year: 2026, month: 10, day: 19, hour: 12)
        )
        let oldValues = RecurringSeriesValues(event: event)
        let newStart = calendar.date(byAdding: .day, value: 1, to: event.startDate)!
        let newEnd = calendar.date(byAdding: .day, value: 1, to: event.endDate)!
        let newValues = seriesValues(for: event, startDate: newStart, endDate: newEnd)

        RecurringSeriesExceptionUpdater.apply(
            from: oldValues,
            to: newValues,
            policy: .preserveIndividualChanges,
            exceptions: [exception]
        )
        event.startDate = newStart
        event.endDate = newEnd

        let results = EventOccurrenceService.occurrences(
            for: event,
            intersecting: DateInterval(
                start: date(year: 2026, month: 10, day: 1),
                end: date(year: 2026, month: 11, day: 1)
            ),
            calendar: calendar,
            exceptions: [exception]
        )
        let movedOccurrence = results.first {
            calendar.isDate($0.originalStartDate, inSameDayAs: date(year: 2026, month: 10, day: 20))
        }

        #expect(movedOccurrence?.title == "개별 운동")
        #expect(calendar.component(.hour, from: movedOccurrence?.startDate ?? .distantPast) == 11)
    }

    @Test("반복 단위 또는 간격 변경은 기존 수정·삭제 예외가 있으면 안전하지 않아 차단한다")
    func recurrenceRuleChangeIsBlockedWhenExceptionsExist() {
        let event = weeklyWorkoutEvent()
        let modified = override(
            for: event,
            originalStart: date(year: 2026, month: 10, day: 19),
            newTitle: "개별 운동",
            newStart: date(year: 2026, month: 10, day: 19, hour: 11),
            newEnd: date(year: 2026, month: 10, day: 19, hour: 12)
        )
        let deleted = exclusion(
            for: event,
            originalStart: date(year: 2026, month: 10, day: 26)
        )

        let unitChange = RecurringSeriesExceptionUpdater.saveRequirement(
            exceptions: [modified],
            oldValues: RecurringSeriesValues(event: event),
            newValues: seriesValues(for: event, repeatUnit: "개월")
        )
        let intervalChange = RecurringSeriesExceptionUpdater.saveRequirement(
            exceptions: [deleted],
            oldValues: RecurringSeriesValues(event: event),
            newValues: seriesValues(for: event, repeatInterval: 2)
        )

        #expect(unitChange == .blockUnsafeRecurrenceChange)
        #expect(intervalChange == .blockUnsafeRecurrenceChange)
        #expect(deleted.isExcluded)
    }

    @Test("전체 제목 변경 후에도 반복 종료일·D-Day 다음 발생일·알림 시각이 유지된다")
    func titleMergePreservesRepeatEndDDayAndNotificationSchedule() {
        let event = weeklyWorkoutEvent()
        event.isDDayEnabled = true
        event.repeatEndDate = date(year: 2026, month: 10, day: 19)
        event.alarmOption = "시작 시간"
        event.alarmTimeIntervalBeforeStart = 0
        let exception = override(
            for: event,
            originalStart: date(year: 2026, month: 10, day: 19),
            newTitle: "개별 운동",
            newStart: date(year: 2026, month: 10, day: 19, hour: 11),
            newEnd: date(year: 2026, month: 10, day: 19, hour: 12)
        )
        exception.overrideAlarmOption = event.alarmOption
        exception.overrideAlarmTimeIntervalBeforeStart = event.alarmTimeIntervalBeforeStart
        let oldValues = RecurringSeriesValues(event: event)
        let newValues = seriesValues(for: event, title: "전체 운동")

        RecurringSeriesExceptionUpdater.apply(
            from: oldValues,
            to: newValues,
            policy: .applyChangedSeriesValues,
            exceptions: [exception]
        )
        event.title = newValues.title

        let next = EventOccurrenceService.nextOccurrenceDate(
            for: event,
            onOrAfter: date(year: 2026, month: 10, day: 19, hour: 0),
            calendar: calendar,
            exceptions: [exception]
        )
        let afterEnd = EventOccurrenceService.nextOccurrenceDate(
            for: event,
            onOrAfter: date(year: 2026, month: 10, day: 20),
            calendar: calendar,
            exceptions: [exception]
        )
        let schedules = EventNotificationPlanner.schedules(
            for: event,
            now: date(year: 2026, month: 10, day: 1),
            calendar: calendar,
            exceptions: [exception]
        )

        #expect(event.isDDayEnabled)
        #expect(next == exception.overrideStartDate)
        #expect(afterEnd == nil)
        #expect(schedules.count == 3)
        #expect(schedules.last?.fireDate == exception.overrideStartDate)
        #expect(schedules.last?.title == "전체 운동")
    }
}

@MainActor
@Suite("SwiftData 스키마 마이그레이션 안전성 (Step 6 안정화)")
struct SchemaMigrationSafetyTests {
    @Test("EventOccurrenceException이 없던 기존 저장소를 새 스키마로 열어도 기존 Event 데이터가 그대로 보존된다")
    func existingStoreWithoutExceptionTableOpensSafelyWithNewSchema() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "MigrationTest-\(UUID().uuidString).store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
        }

        // 1단계: EventOccurrenceException이 존재하기 이전 스키마로 저장소를 만들고 실제 데이터를 저장한다
        // (기존 사용자의 실기기 저장소 상태를 흉내 낸다 — 메모리가 아니라 실제 파일 기반 저장소다).
        let legacySchema = Schema([Event.self, ExternalEventDDaySetting.self])
        let legacyConfig = ModelConfiguration(schema: legacySchema, url: storeURL, cloudKitDatabase: .none)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: [legacyConfig])
        let legacyContext = ModelContext(legacyContainer)

        let existingEvent = Event(
            title: "기존 일정",
            isAllDay: false,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3_600),
            color: "파란색",
            alarmOption: "없음",
            alarmTimeIntervalBeforeStart: nil,
            alarmCustomValue: 1,
            alarmCustomUnit: "일",
            repeatUnit: "반복 안 함",
            repeatInterval: 1,
            memo: "마이그레이션 전 메모",
            isDDayEnabled: true
        )
        legacyContext.insert(existingEvent)
        try legacyContext.save()
        let savedEventID = existingEvent.id

        // 2단계: 같은 파일을 EventOccurrenceException이 추가된 새 스키마로 다시 연다(앱 업데이트 시뮬레이션).
        let newSchema = Schema([Event.self, ExternalEventDDaySetting.self, EventOccurrenceException.self])
        let newConfig = ModelConfiguration(schema: newSchema, url: storeURL, cloudKitDatabase: .none)
        let newContainer = try ModelContainer(for: newSchema, configurations: [newConfig])
        let newContext = ModelContext(newContainer)

        let migratedEvents = try newContext.fetch(FetchDescriptor<Event>())
        #expect(migratedEvents.count == 1)
        #expect(migratedEvents.first?.id == savedEventID)
        #expect(migratedEvents.first?.title == "기존 일정")
        #expect(migratedEvents.first?.memo == "마이그레이션 전 메모")
        #expect(migratedEvents.first?.isDDayEnabled == true)
        #expect(migratedEvents.first?.repeatEndDate == nil)

        // 3단계: 새로 추가된 테이블(EventOccurrenceException)도 정상적으로 쓸 수 있어야 한다.
        let exception = EventOccurrenceException(
            eventID: savedEventID,
            originalOccurrenceStartDate: Date(),
            isExcluded: true
        )
        newContext.insert(exception)
        try newContext.save()

        let exceptions = try newContext.fetch(FetchDescriptor<EventOccurrenceException>())
        #expect(exceptions.count == 1)

        // 4단계: 기존 Event는 여전히 그대로다(새 테이블 추가가 기존 데이터에 영향을 주지 않았다).
        let eventsAfter = try newContext.fetch(FetchDescriptor<Event>())
        #expect(eventsAfter.count == 1)
        #expect(eventsAfter.first?.id == savedEventID)
    }
}

@Suite("D-Day 하루 차이 의심 사례 재현 (Step 6 안정화)")
struct DDayOffByOneReproductionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func date(year: Int, month: Int, day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// 보고된 사례 그대로: 매년 10월 10일 반복되는 생일(아주 오래전부터 반복 중이라고 가정).
    private func birthdayEvent() -> Event {
        Event(
            title: "생일",
            isAllDay: false,
            startDate: date(year: 2000, month: 10, day: 10),
            endDate: date(year: 2000, month: 10, day: 10),
            color: "파란색",
            alarmOption: "없음",
            alarmTimeIntervalBeforeStart: nil,
            alarmCustomValue: 1,
            alarmCustomUnit: "일",
            repeatUnit: "년",
            repeatInterval: 1,
            memo: ""
        )
    }

    /// nextOccurrenceDate + daysRemaining을 실제 위젯·편집 화면과 같은 방식(두 단계)으로 조합해,
    /// "기준 날짜"에 위젯이 실제로 보여줄 D-Day 문구를 재현한다.
    private func widgetStyleDDayText(onOrAfter now: Date, event: Event) -> String {
        let targetDate = EventOccurrenceService.nextOccurrenceDate(
            for: event, onOrAfter: now, calendar: calendar
        ) ?? event.startDate
        let days = DDayCalculator.daysRemaining(until: targetDate, now: now, calendar: calendar)
        return DDayCalculator.displayText(forDaysRemaining: days)
    }

    @Test(
        "보고된 표를 그대로 재현한다: 10월 10일 생일 반복 일정의 날짜별 D-Day 문구",
        arguments: [
            (2026, 10, 9, "D-1"),
            (2026, 10, 10, "D-Day"),
            (2026, 10, 11, "D-364"),
            (2026, 10, 12, "D-363"),
            (2027, 10, 9, "D-1"),
            (2027, 10, 10, "D-Day")
        ]
    )
    func reproducesReportedTable(_ case_: (year: Int, month: Int, day: Int, expected: String)) {
        let event = birthdayEvent()
        let now = date(year: case_.year, month: case_.month, day: case_.day)
        let text = widgetStyleDDayText(onOrAfter: now, event: event)
        #expect(text == case_.expected)
    }

    @Test("자정 직후(00:00:01)와 늦은 밤(23:59:59) 모두 같은 날짜 기준으로 같은 D-Day를 낸다")
    func timeOfDayDoesNotAffectDayLevelCalculation() {
        let event = birthdayEvent()
        let earlyMorning = calendar.date(
            byAdding: DateComponents(hour: 0, minute: 0, second: 1),
            to: calendar.startOfDay(for: date(year: 2026, month: 10, day: 11))
        )!
        let lateNight = calendar.date(
            byAdding: DateComponents(hour: 23, minute: 59, second: 59),
            to: calendar.startOfDay(for: date(year: 2026, month: 10, day: 11))
        )!

        #expect(widgetStyleDDayText(onOrAfter: earlyMorning, event: event) == "D-364")
        #expect(widgetStyleDDayText(onOrAfter: lateNight, event: event) == "D-364")
    }

    @Test("윤년을 지나는 반복 생일도 올바르게 계산한다(2024-02-29 생일, 2025년은 평년)")
    func leapYearBirthdayAcrossNonLeapYear() {
        let event = Event(
            title: "윤년 생일",
            isAllDay: false,
            startDate: date(year: 2024, month: 2, day: 29),
            endDate: date(year: 2024, month: 2, day: 29),
            color: "파란색",
            alarmOption: "없음",
            alarmTimeIntervalBeforeStart: nil,
            alarmCustomValue: 1,
            alarmCustomUnit: "일",
            repeatUnit: "년",
            repeatInterval: 1,
            memo: ""
        )
        // 평년엔 2/29가 없어 validatedDate가 건너뛰므로, 다음 2/29는 2028년(윤년)이다.
        let now = date(year: 2025, month: 3, day: 1)
        #expect(widgetStyleDDayText(onOrAfter: now, event: event) == "D-1095")
    }

    @Test("종일 일정으로 설정된 반복 생일도 날짜 기준으로 동일하게 계산한다")
    func allDayBirthdayCalculatesTheSameWay() {
        let event = Event(
            title: "생일(종일)",
            isAllDay: true,
            startDate: date(year: 2000, month: 10, day: 10, hour: 0),
            endDate: date(year: 2000, month: 10, day: 10, hour: 0),
            color: "파란색",
            alarmOption: "없음",
            alarmTimeIntervalBeforeStart: nil,
            alarmCustomValue: 1,
            alarmCustomUnit: "일",
            repeatUnit: "년",
            repeatInterval: 1,
            memo: ""
        )
        let now = date(year: 2026, month: 10, day: 11)
        #expect(widgetStyleDDayText(onOrAfter: now, event: event) == "D-364")
    }
}

@Suite("WidgetReloadDebouncer")
@MainActor
struct WidgetReloadDebouncerTests {
    @Test("짧은 시간에 반복된 갱신 요청은 한 번만 실행된다")
    func coalescesRepeatedRequests() async throws {
        var reloadCount = 0
        let debouncer = WidgetReloadDebouncer(delay: .milliseconds(20)) {
            reloadCount += 1
        }

        debouncer.request()
        debouncer.request()
        debouncer.request()
        try await Task.sleep(for: .milliseconds(80))

        #expect(reloadCount == 1)
    }

    @Test("즉시 갱신은 대기 중 요청을 취소해 중복 실행하지 않는다")
    func immediateReloadCancelsPendingRequest() async throws {
        var reloadCount = 0
        let debouncer = WidgetReloadDebouncer(delay: .milliseconds(40)) {
            reloadCount += 1
        }

        debouncer.request()
        debouncer.reloadNow()
        try await Task.sleep(for: .milliseconds(100))

        #expect(reloadCount == 1)
    }
}
