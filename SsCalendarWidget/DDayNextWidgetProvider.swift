import WidgetKit

/// 잠금화면 D-Day Next 위젯(`accessoryRectangular`)의 타임라인 제공자.
/// D-Day 위젯이 보여주는 일정 다음으로 가까운 일정을 보여준다. 조회 기준은 DDayWidgetProvider와
/// 완전히 같다(DDayWidgetSource.items(limit: 2)의 두 번째 항목).
struct DDayNextWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DDayWidgetEntry {
        .nextPlaceholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DDayWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.nextPlaceholder)
            return
        }

        Task { @MainActor in
            completion(makeTimeline(now: Date()).entries.first ?? .empty(for: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DDayWidgetEntry>) -> Void) {
        Task { @MainActor in
            completion(makeTimeline(now: Date()))
        }
    }

    @MainActor
    private func makeTimeline(now: Date) -> Timeline<DDayWidgetEntry> {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now.addingTimeInterval(86_400)
        let showsEventTitles = LockScreenWidgetMoments.showsEventTitles()

        let items = DDayWidgetSource.items(now: now, limit: 2)
        let secondItem = items.count > 1 ? items[1] : nil
        let summary = secondItem.map { item in
            DDayWidgetItemSummary(
                displayTitle: showsEventTitles ? item.occurrence.title : String(localized: "일정 있음"),
                isSensitiveTitle: showsEventTitles,
                startDate: item.occurrence.startDate,
                daysRemaining: item.daysRemaining
            )
        }

        let entry = DDayWidgetEntry(date: now, item: summary)
        return Timeline(entries: [entry], policy: .after(nextMidnight))
    }
}
