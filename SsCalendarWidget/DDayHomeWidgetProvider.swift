import WidgetKit

/// 홈 화면 D-Day 위젯(Small/Medium)의 타임라인 제공자. 잠금화면 D-Day 위젯과 같은
/// DDayWidgetSource를 공유해 항상 같은 정렬·필터 기준을 쓴다.
struct DDayHomeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DDayHomeWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DDayHomeWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        Task { @MainActor in
            completion(makeTimeline(now: Date()).entries.first ?? .empty(for: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DDayHomeWidgetEntry>) -> Void) {
        Task { @MainActor in
            completion(makeTimeline(now: Date()))
        }
    }

    @MainActor
    private func makeTimeline(now: Date) -> Timeline<DDayHomeWidgetEntry> {
        let nextMidnight = CalendarWidgetCalendar.nextMidnight(after: now)
        let showsEventTitles = LockScreenWidgetMoments.showsEventTitles()

        // Medium이 최대 2건을 보여주므로 여기서 2개까지만 가져온다(Small은 뷰에서 첫 번째만 쓴다).
        let items = DDayWidgetSource.items(now: now, limit: 2).map { item in
            DDayHomeWidgetItem(
                displayTitle: showsEventTitles ? item.occurrence.title : String(localized: "일정 있음"),
                isSensitiveTitle: showsEventTitles,
                startDate: item.occurrence.startDate,
                originalStartDate: item.occurrence.originalStartDate,
                localEventID: item.occurrence.localEventID,
                daysRemaining: item.daysRemaining
            )
        }

        let entry = DDayHomeWidgetEntry(date: now, items: items)
        return Timeline(entries: [entry], policy: .after(nextMidnight))
    }
}
