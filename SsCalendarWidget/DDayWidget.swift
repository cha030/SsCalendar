import SwiftUI
import WidgetKit

/// 잠금화면 D-Day 위젯. D-Day가 켜진 일정 중 가장 가까운 것 하나를 보여준다(Step 5-2,
/// accessoryRectangular 전용). 짝을 이루는 DDayNextWidget과 데이터 조회를 공유한다(DDayWidgetSource).
struct DDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: DDayWidgetConstants.lockScreenKind,
            provider: DDayWidgetProvider()
        ) { entry in
            DDayWidgetView(entry: entry)
        }
        .configurationDisplayName("D-Day — 가장 가까운 일정")
        .description("잠금화면에서 가장 가까운 D-Day 일정을 확인합니다.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    DDayWidget()
} timeline: {
    DDayWidgetEntry.placeholder
}
