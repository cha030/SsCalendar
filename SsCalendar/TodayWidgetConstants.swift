import Foundation

/// 잠금화면 Today/Next 위젯(`accessoryRectangular`)의 kind와 설정 키.
/// 앱과 위젯이 함께 쓰므로 위젯 폴더에 심볼릭 링크로 공유한다(CalendarWidgetConstants와 동일한 패턴).
enum TodayWidgetConstants {
    static let kind = "SsCalendarTodayWidget"
    /// Next 위젯은 Today와 별도의 kind를 쓴다. 사용자가 둘 중 하나만 추가하거나 나란히 추가할 수 있어야 하기 때문이다.
    static let nextKind = "SsCalendarNextWidget"

    /// 잠금화면에 실제 일정 제목을 보여줄지 여부(App Group UserDefaults). 기본값 ON(표시).
    /// 앱 화면은 `@AppStorage(showEventTitlesKey, store: SystemCalendarService.settingsStore)`로 읽고 쓴다.
    static let showEventTitlesKey = "todayWidgetShowEventTitles"

    /// 위젯 익스텐션에서 쓰는 읽기 전용 접근자. 값이 저장된 적이 없으면 기본값 ON으로 본다.
    /// (`UserDefaults.bool(forKey:)`는 키가 없을 때 false를 반환하므로 직접 구분해야 한다.)
    static func showsEventTitles(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: showEventTitlesKey) != nil else { return true }
        return defaults.bool(forKey: showEventTitlesKey)
    }
}
