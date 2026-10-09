import SwiftUI
import WidgetKit

/// 잠금화면 Today 위젯. 가장 중요한 일정 하나(진행 중인 일정, 없으면 가장 가까운 예정 일정)를 크게 보여준다
/// (Step 3, accessoryRectangular 전용). 기존 월간 홈 위젯(SsCalendarWidget)과는 별도의 kind·Entry·Provider·View를 쓴다.
/// 짝을 이루는 Next 위젯(NextWidget.swift)과 데이터 조회·타임라인 계산을 공유한다(LockScreenWidgetMoments).
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: TodayWidgetConstants.kind,
            provider: TodayWidgetProvider()
        ) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today — 첫 번째 일정")
        .description("잠금화면에서 진행 중이거나 가장 가까운 일정 하나를 확인합니다.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    TodayWidgetEntry.placeholder
}
