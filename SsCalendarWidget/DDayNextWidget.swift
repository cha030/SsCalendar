import SwiftUI
import WidgetKit

/// 잠금화면 D-Day Next 위젯. DDayWidget이 보여주는 일정 다음으로 가까운 D-Day 일정을 보여준다
/// (Step 5-2, accessoryRectangular 전용). Today/Next처럼 사용자가 둘 중 하나만 추가하거나
/// 나란히 추가할 수 있도록 별도 kind·Widget을 쓴다.
struct DDayNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: DDayWidgetConstants.lockScreenNextKind,
            provider: DDayNextWidgetProvider()
        ) { entry in
            DDayNextWidgetView(entry: entry)
        }
        .configurationDisplayName("D-Day — 두 번째로 가까운 일정")
        .description("잠금화면에서 두 번째로 가까운 D-Day 일정을 확인합니다.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    DDayNextWidget()
} timeline: {
    DDayWidgetEntry.nextPlaceholder
}
