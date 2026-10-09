import SwiftUI
import WidgetKit

/// 잠금화면 Next 위젯 전용 뷰. Today와 본문(LockScreenWidgetContent)을 공유하고 빈 상태 문구만 다르다.
struct NextWidgetView: View {
    let entry: TodayWidgetEntry

    var body: some View {
        LockScreenWidgetContent(
            occurrence: entry.occurrence,
            emptyText: String(localized: "다음 일정 없음")
        )
        .widgetURL(CalendarWidgetDeepLink.dayURL(for: entry.date))
    }
}

#Preview("Next", as: .accessoryRectangular) {
    NextWidget()
} timeline: {
    TodayWidgetEntry.nextPlaceholder
    TodayWidgetEntry.empty(for: .now)
}
