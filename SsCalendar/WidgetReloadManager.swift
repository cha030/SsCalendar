import WidgetKit

enum WidgetReloadManager {
    static func reloadCalendar() {
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
    }
}
