import SwiftUI
import WidgetKit

/// 잠금화면 Next 위젯. Today 다음으로 중요한 일정 하나를 보여준다(Step 3, accessoryRectangular 전용).
/// Today와 나란히 추가하면 2+2칸을, Today 없이 이것만 추가해도 2칸을 차지한다.
/// Today(TodayWidget.swift)와 데이터 조회·타임라인 계산을 공유한다(LockScreenWidgetMoments).
struct NextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: TodayWidgetConstants.nextKind,
            provider: NextWidgetProvider()
        ) { entry in
            NextWidgetView(entry: entry)
        }
        .configurationDisplayName("Today — 두 번째 일정")
        .description("잠금화면에서 그다음으로 가까운 일정을 확인합니다.")
        .supportedFamilies([.accessoryRectangular])
    }
}
