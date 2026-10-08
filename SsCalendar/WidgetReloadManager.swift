import WidgetKit

@MainActor
enum WidgetReloadManager {
    private static var pendingReloadTask: Task<Void, Never>?

    /// 기존 호출부를 위한 즉시 갱신 요청이다.
    static func reloadCalendar() {
        pendingReloadTask?.cancel()
        pendingReloadTask = nil
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
    }

    /// 짧은 시간에 몰린 변경 알림을 하나의 갱신 요청으로 합친다.
    /// WidgetKit은 실제 갱신 시점과 횟수를 시스템 예산에 따라 결정한다.
    static func requestCalendarReload() {
        pendingReloadTask?.cancel()
        pendingReloadTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
            pendingReloadTask = nil
        }
    }
}
