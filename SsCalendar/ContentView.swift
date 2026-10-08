import SwiftUI
import UIKit

struct ContentView: View {
    @State private var systemCalendarRefreshGeneration = 0

    var body: some View {
        CalendarView(
            systemCalendarRefreshGeneration: systemCalendarRefreshGeneration
        )
        .task {
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
