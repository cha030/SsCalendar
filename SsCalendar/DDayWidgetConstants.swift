import Foundation

/// D-Day 위젯들의 kind(Step 5-2). 앱(WidgetReloadManager)과 위젯이 함께 쓰므로
/// 위젯 폴더에 심볼릭 링크로 공유한다(CalendarWidgetConstants/TodayWidgetConstants와 같은 패턴).
enum DDayWidgetConstants {
    /// 잠금화면: 가장 가까운 D-Day 일정.
    static let lockScreenKind = "SsCalendarDDayWidget"
    /// 잠금화면: 두 번째로 가까운 D-Day 일정. Today/Next와 같은 이유로 별도 kind를 쓴다
    /// (사용자가 둘 중 하나만 추가하거나 나란히 추가할 수 있어야 한다).
    static let lockScreenNextKind = "SsCalendarDDayNextWidget"
    /// 홈 화면(Small/Medium).
    static let homeKind = "SsCalendarDDayHomeWidget"
}
