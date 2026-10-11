import WidgetKit

@MainActor
final class WidgetReloadDebouncer {
    private var pendingReloadTask: Task<Void, Never>?

    private let delay: Duration
    private let reloadAction: @MainActor () -> Void

    init(
        delay: Duration = .milliseconds(250),
        reloadAction: @escaping @MainActor () -> Void
    ) {
        self.delay = delay
        self.reloadAction = reloadAction
    }

    func reloadNow() {
        pendingReloadTask?.cancel()
        pendingReloadTask = nil
        reloadAction()
    }

    func request() {
        pendingReloadTask?.cancel()
        pendingReloadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            reloadAction()
            pendingReloadTask = nil
        }
    }
}

@MainActor
enum WidgetReloadManager {
    private static let debouncer = WidgetReloadDebouncer(reloadAction: reloadAllTimelines)

    /// 기존 호출부를 위한 즉시 갱신 요청이다. 월간 홈 위젯과 잠금화면 Today·Next 위젯을 모두 갱신한다.
    /// 세 위젯이 같은 로컬·시스템 일정 데이터를 사용하므로 kind별로 호출부를 나누지 않는다.
    static func reloadCalendar() {
        debouncer.reloadNow()
    }

    /// 짧은 시간에 몰린 변경 알림을 하나의 갱신 요청으로 합친다.
    /// WidgetKit은 실제 갱신 시점과 횟수를 시스템 예산에 따라 결정한다.
    static func requestCalendarReload() {
        debouncer.request()
    }

    private static func reloadAllTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.nextKind)
        WidgetCenter.shared.reloadTimelines(ofKind: DDayWidgetConstants.lockScreenKind)
        WidgetCenter.shared.reloadTimelines(ofKind: DDayWidgetConstants.lockScreenNextKind)
        WidgetCenter.shared.reloadTimelines(ofKind: DDayWidgetConstants.homeKind)
    }
}
