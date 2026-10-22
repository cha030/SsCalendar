import SwiftData
import SwiftUI
import WidgetKit

/// Today·Next 잠금화면 위젯이 공유하는 데이터 조회·타임라인 경계 계산.
/// 두 위젯이 완전히 같은 시각·같은 일정 목록을 기준으로 계산해야 같은 경계에서 함께 전환되므로,
/// 일정 조회와 엔트리 시각 계산을 이 한 곳에 모은다. TodayWidgetProvider/NextWidgetProvider는
/// 여기서 만든 결과 중 자신이 보여줄 한 일정(`today`/`next`)만 골라 쓴다.
@MainActor
enum LockScreenWidgetMoments {
    /// 한 번의 타임라인에서 만들 엔트리 수 상한. 일정이 많아도 과도한 엔트리를 만들지 않는다.
    private static let maximumEntries = 32

    struct Moment {
        let date: Date
        let status: TodayWidgetStatus
    }

    /// - Returns: 오늘 안에서 상태가 바뀔 수 있는 시각마다 하나씩 만든 모먼트 목록과,
    ///   그 타임라인을 다시 요청할 시각(자정).
    static func make(now: Date) -> (moments: [Moment], refreshAt: Date) {
        let calendar = DeviceCalendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            let fallback = now.addingTimeInterval(3_600)
            return ([Moment(date: now, status: .empty)], fallback)
        }

        let todayInterval = DateInterval(start: dayStart, end: dayEnd)
        let occurrences = todaysOccurrences(in: todayInterval, calendar: calendar)

        // Today/Next 상태가 바뀔 수 있는 시각(오늘 일정들의 시작·종료)만 타임라인 엔트리로 만든다.
        // Set으로 모아 같은 시각이 겹쳐도 엔트리가 중복되지 않는다. 자정도 포함해 다음 날로 자연히 넘어가게 한다.
        var boundaries: Set<Date> = [max(now, dayStart), dayEnd]
        for occurrence in occurrences where !occurrence.isAllDay {
            if occurrence.startDate > now { boundaries.insert(occurrence.startDate) }
            if occurrence.endDate > now && occurrence.endDate < dayEnd { boundaries.insert(occurrence.endDate) }
        }

        let moments = boundaries.sorted().prefix(maximumEntries).map { entryDate in
            Moment(
                date: entryDate,
                status: TodayWidgetStatusResolver.status(from: occurrences, now: entryDate, calendar: calendar)
            )
        }

        // 자정이 지나면 오늘 일정이 아예 달라지므로 그 시점에 새 타임라인을 다시 요청한다.
        // 그 전까지는 위에서 만든 모먼트들이 각자의 시각에 맞춰 자동으로 전환된다.
        return (Array(moments), dayEnd)
    }

    /// 설정에 저장된 "잠금화면 일정 제목 표시" 값. 값이 없으면 기본값 ON.
    static func showsEventTitles() -> Bool {
        SystemCalendarQuery.sharedDefaults().map(TodayWidgetConstants.showsEventTitles(in:)) ?? true
    }

    static func summary(
        for occurrence: CalendarDisplayOccurrence?,
        isOngoing: Bool,
        showsEventTitles: Bool
    ) -> TodayWidgetOccurrenceSummary? {
        guard let occurrence else { return nil }

        return TodayWidgetOccurrenceSummary(
            displayTitle: showsEventTitles ? occurrence.title : String(localized: "일정 있음"),
            isSensitiveTitle: showsEventTitles,
            isAllDay: occurrence.isAllDay,
            isOngoing: isOngoing,
            startDate: occurrence.startDate,
            endDate: occurrence.endDate
        )
    }

    // MARK: - 일정 조회

    private static func todaysOccurrences(in interval: DateInterval, calendar: Calendar) -> [CalendarDisplayOccurrence] {
        localOccurrences(in: interval, calendar: calendar) + systemOccurrences(in: interval)
    }

    /// 기존 반복 엔진(EventOccurrenceService)을 그대로 재사용한다. 색상은 Today/Next 위젯에서 쓰지 않으므로
    /// EventColor(앱 전용 타입)에 의존하지 않고 더미 값을 채운다.
    private static func localOccurrences(in interval: DateInterval, calendar: Calendar) -> [CalendarDisplayOccurrence] {
        do {
            let container = try WidgetDataStore.makeModelContainer()
            let context = ModelContext(container)
            let events = try context.fetch(FetchDescriptor<Event>())

            return EventOccurrenceService.occurrences(for: events, intersecting: interval, calendar: calendar)
                .map { occurrence in
                    let startDate = occurrence.isAllDay
                        ? AllDayDate.displayDate(fromStorageDate: occurrence.startDate, calendar: calendar)
                        : occurrence.startDate
                    let endDate = occurrence.isAllDay
                        ? AllDayDate.displayDate(fromStorageDate: occurrence.endDate, calendar: calendar)
                        : occurrence.endDate
                    return CalendarDisplayOccurrence(
                        id: "local:\(occurrence.event.id.uuidString):\(occurrence.startDate.timeIntervalSince1970)",
                        source: .local(eventID: occurrence.event.id),
                        title: occurrence.event.title,
                        isAllDay: occurrence.isAllDay,
                        startDate: startDate,
                        endDate: endDate,
                        color: .clear
                    )
                }
        } catch {
            return []
        }
    }

    /// 앱과 동일한 규칙(연동 ON, Full Access, 숨긴 캘린더 제외)으로 시스템 일정을 읽는다.
    private static func systemOccurrences(in interval: DateInterval) -> [CalendarDisplayOccurrence] {
        guard let defaults = SystemCalendarQuery.sharedDefaults() else { return [] }
        return SystemCalendarQuery.enabledResults(in: interval, defaults: defaults).map(\.occurrence)
    }
}

/// 잠금화면 Today 위젯(`accessoryRectangular`)의 타임라인 제공자.
/// 진행 중인 일정이 있으면 그 일정을, 없으면 가장 가까운 예정 일정을 보여준다.
struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        Task { @MainActor in
            completion(makeTimeline(now: Date()).entries.first ?? .empty(for: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        Task { @MainActor in
            completion(makeTimeline(now: Date()))
        }
    }

    @MainActor
    private func makeTimeline(now: Date) -> Timeline<TodayWidgetEntry> {
        let (moments, refreshAt) = LockScreenWidgetMoments.make(now: now)
        let showsEventTitles = LockScreenWidgetMoments.showsEventTitles()

        let entries = moments.map { moment in
            TodayWidgetEntry(
                date: moment.date,
                dateString: CalendarWidgetCalendar.dateString(for: moment.date, calendar: DeviceCalendar.current),
                occurrence: LockScreenWidgetMoments.summary(
                    for: moment.status.today,
                    isOngoing: moment.status.isTodayOngoing,
                    showsEventTitles: showsEventTitles
                )
            )
        }

        return Timeline(entries: entries, policy: .after(refreshAt))
    }
}
