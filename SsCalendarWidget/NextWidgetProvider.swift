import WidgetKit

/// 잠금화면 Next 위젯(`accessoryRectangular`)의 타임라인 제공자.
/// Today 위젯이 고른 일정 다음으로 가장 빠른 예정 일정을 보여준다.
/// 일정 조회·타임라인 경계 계산은 Today와 완전히 같은 기준을 쓰도록 `LockScreenWidgetMoments`를 공유한다.
struct NextWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        .nextPlaceholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.nextPlaceholder)
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
            // Next는 항상 아직 시작하지 않은 일정이므로 "진행" 표시가 없다.
            TodayWidgetEntry(
                date: moment.date,
                dateString: CalendarWidgetCalendar.dateString(for: moment.date),
                occurrence: LockScreenWidgetMoments.summary(
                    for: moment.status.next,
                    isOngoing: false,
                    showsEventTitles: showsEventTitles
                )
            )
        }

        return Timeline(entries: entries, policy: .after(refreshAt))
    }
}
