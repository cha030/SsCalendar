import SwiftUI
import WidgetKit

/// 잠금화면 D-Day 위젯(`accessoryRectangular`)의 타임라인 제공자.
/// D-Day가 켜진 일정 중 가장 가까운 것을 보여준다. D-Day는 자정에만 값이 바뀌므로(날짜 단위
/// 계산) Today/Next처럼 하루 안에서 여러 엔트리를 미리 만들 필요가 없다 — 다음 자정에 한 번만
/// 다시 계산해도 충분하다.
struct DDayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DDayWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DDayWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
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
        let nextMidnight = CalendarWidgetCalendar.nextMidnight(after: now)
        let showsEventTitles = LockScreenWidgetMoments.showsEventTitles()

        // Next 위젯과 같은 조회(최대 2건)를 공유해 둘이 항상 같은 정렬 기준을 쓰게 한다.
        let items = DDayWidgetSource.items(now: now, limit: 2)
        let summary = items.first.map { item in
            DDayWidgetItemSummary(
                displayTitle: showsEventTitles ? item.occurrence.title : String(localized: "일정 있음"),
                isSensitiveTitle: showsEventTitles,
                startDate: item.occurrence.startDate,
                dateString: CalendarWidgetCalendar.dateString(for: item.occurrence.startDate),
                daysRemaining: item.daysRemaining
            )
        }

        let entry = DDayWidgetEntry(
            date: now,
            dateString: CalendarWidgetCalendar.dateString(for: now),
            item: summary
        )
        return Timeline(entries: [entry], policy: .after(nextMidnight))
    }
}
