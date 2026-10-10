import SwiftUI
import WidgetKit

/// 홈 화면 D-Day 위젯(Step 5-2). Small은 가장 가까운 D-Day 1건, Medium은 가까운 2건을 보여준다.
/// 기존 월간 홈 위젯(SsCalendarWidget)과는 별도의 kind·Entry·Provider·View를 쓴다.
struct DDayHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: DDayWidgetConstants.homeKind,
            provider: DDayHomeWidgetProvider()
        ) { entry in
            DDayHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("D-Day")
        .description("다가오는 D-Day 일정을 홈 화면에서 확인합니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    DDayHomeWidget()
} timeline: {
    DDayHomeWidgetEntry.placeholder
}
