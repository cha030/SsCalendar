import SwiftUI
import UIKit

struct ContentView: View {
    @State private var systemCalendarRefreshGeneration = 0

    var body: some View {
        CalendarView(
            systemCalendarRefreshGeneration: systemCalendarRefreshGeneration
        )
        .task {
            // 최초 실행에서는 didBecomeActive 알림보다 이 task 등록이 늦을 수 있으므로
            // 현재 활성 상태도 한 번 처리해 외부 일정과 위젯 타임라인을 놓치지 않는다.
            SystemCalendarService.shared.handleAppDidBecomeActive()
            systemCalendarRefreshGeneration += 1

            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didBecomeActiveNotification
            ) {
                SystemCalendarService.shared.handleAppDidBecomeActive()
                systemCalendarRefreshGeneration += 1
            }
        }
    }
}

#Preview {
    ContentView()
}
