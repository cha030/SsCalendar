import EventKit
import Foundation
import Observation
import SwiftUI

/// iOS 시스템 캘린더(EventKit) 읽기 전용 서비스.
/// 일정은 복사·동기화하지 않고, 화면이 요청한 날짜 범위만 그때그때 조회해 표시 모델로 변환한다.
@MainActor
@Observable
final class SystemCalendarService {
    static let shared = SystemCalendarService()

    /// 설정 화면의 "iPhone 캘린더 일정 표시" 토글. 기본값 OFF.
    /// `@AppStorage`로 읽을 때는 반드시 `store: SystemCalendarService.settingsStore`를 함께 지정한다.
    static let isEnabledStorageKey = SystemCalendarQuery.isEnabledKey

    /// 시스템 캘린더 관련 설정(표시 ON/OFF, 숨긴 캘린더, 첫 안내 여부)을 모두 저장하는 App Group 저장소.
    /// 위젯 등 다른 타깃에서도 같은 설정을 읽을 수 있도록 한 곳에 모은다.
    static let settingsStore: UserDefaults = {
        let defaults = SystemCalendarQuery.sharedDefaults() ?? .standard
        migrateLegacyEnabledSetting(to: defaults)
        return defaults
    }()

    /// 이전 빌드는 표시 ON/OFF 값을 앱 전용 UserDefaults.standard에 저장했다.
    /// App Group에 값이 없을 때만 기존 값을 옮겨 사용자의 선택을 유지하고, 이전 값은 정리한다.
    private static func migrateLegacyEnabledSetting(to defaults: UserDefaults) {
        let legacyDefaults = UserDefaults.standard
        guard
            defaults !== legacyDefaults,
            let legacyValue = legacyDefaults.object(forKey: isEnabledStorageKey) as? Bool
        else {
            return
        }

        if defaults.object(forKey: isEnabledStorageKey) == nil {
            defaults.set(legacyValue, forKey: isEnabledStorageKey)
        }
        legacyDefaults.removeObject(forKey: isEnabledStorageKey)
    }

    /// 사용자가 표시 OFF로 선택한 캘린더의 calendarIdentifier 목록(App Group UserDefaults).
    /// "숨김 목록"으로 저장하므로 새로 추가된 캘린더는 자동으로 표시 대상(ON)이 된다.
    private static let hiddenCalendarIDsKey = SystemCalendarQuery.hiddenCalendarIDsKey
    /// 첫 연동 시 "표시할 캘린더 선택" 안내를 이미 보여줬는지 여부(App Group UserDefaults).
    private static let selectionIntroShownKey = SystemCalendarQuery.selectionIntroShownKey

    /// 시스템 캘린더 데이터나 권한이 바뀔 때마다 증가한다. 화면은 이 값을 조회 트리거로 사용한다.
    private(set) var changeToken = 0
    private(set) var authorizationStatus: EKAuthorizationStatus
    private(set) var hiddenCalendarIDs: Set<String>

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let sharedDefaults = SystemCalendarService.settingsStore
    @ObservationIgnored private var changeObservation: Task<Void, Never>?

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        hiddenCalendarIDs = SystemCalendarQuery.hiddenCalendarIDs(in: sharedDefaults)
        changeObservation = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: .EKEventStoreChanged)
                .map { $0.name }
            for await _ in changes {
                self?.changeToken += 1
                WidgetReloadManager.requestCalendarReload()
            }
        }
    }

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    /// 사용자가 앱 밖(설정 앱)에서 권한을 바꿨을 수 있으므로 현재 상태를 다시 읽는다.
    func refreshAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status != authorizationStatus else { return }
        authorizationStatus = status
        changeToken += 1
        WidgetReloadManager.requestCalendarReload()
    }

    /// Full Access 권한을 요청한다. 이미 결정된 경우 시스템 팝업 없이 현재 결과를 반환한다.
    func requestFullAccess() async -> Bool {
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            granted = false
        }

        if granted {
            // 권한 획득 전에 만들어진 store는 reset 후에야 일정을 반환한다.
            store.reset()
        }
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        changeToken += 1
        WidgetReloadManager.requestCalendarReload()
        return granted
    }

    /// 앱이 백그라운드에서 돌아오면 원격 캘린더 소스를 새로 확인한다.
    /// 변경 여부를 시스템이 즉시 보장하지 않으므로, 연동 중인 경우 갱신을 요청한다.
    func handleAppDidBecomeActive() {
        refreshAuthorizationStatus()

        guard
            sharedDefaults.bool(forKey: Self.isEnabledStorageKey),
            hasFullAccess
        else {
            return
        }

        store.refreshSourcesIfNecessary()
        WidgetReloadManager.requestCalendarReload()
    }

    // MARK: - 표시할 캘린더 선택

    /// 계정(source)별로 묶은 이벤트 캘린더 목록. 권한이 없으면 빈 배열.
    func calendarGroups() -> [SystemCalendarSourceGroup] {
        // 캘린더 추가/삭제(EKEventStoreChanged) 시 목록을 그리는 화면이 다시 그려지도록 추적한다.
        _ = changeToken
        guard hasFullAccess else { return [] }

        let calendarsBySource = Dictionary(grouping: store.calendars(for: .event)) {
            $0.source?.sourceIdentifier ?? ""
        }

        return calendarsBySource
            .map { sourceID, calendars in
                SystemCalendarSourceGroup(
                    id: sourceID,
                    title: calendars.first?.source?.title ?? "기타",
                    calendars: calendars
                        .map { calendar in
                            SystemCalendarInfo(
                                id: calendar.calendarIdentifier,
                                title: calendar.title,
                                color: calendar.cgColor.map { Color(cgColor: $0) } ?? .gray
                            )
                        }
                        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func isCalendarVisible(_ calendarID: String) -> Bool {
        !hiddenCalendarIDs.contains(calendarID)
    }

    func setCalendar(_ calendarID: String, isVisible: Bool) {
        if isVisible {
            hiddenCalendarIDs.remove(calendarID)
        } else {
            hiddenCalendarIDs.insert(calendarID)
        }
        sharedDefaults.set(
            hiddenCalendarIDs.sorted(),
            forKey: Self.hiddenCalendarIDsKey
        )
        changeToken += 1
        WidgetReloadManager.requestCalendarReload()
    }

    var hasShownSelectionIntro: Bool {
        sharedDefaults.bool(forKey: Self.selectionIntroShownKey)
    }

    func markSelectionIntroShown() {
        sharedDefaults.set(true, forKey: Self.selectionIntroShownKey)
    }

    // MARK: - 일정 조회

    /// 지정한 범위와 겹치는 시스템 일정을 표시 모델로 반환한다.
    /// 권한이 없거나 표시 대상 캘린더가 하나도 없으면 빈 배열.
    /// 조회·필터 규칙은 위젯과 공유하는 SystemCalendarQuery에 있다.
    func occurrences(in interval: DateInterval) -> [CalendarDisplayOccurrence] {
        guard hasFullAccess else { return [] }

        return SystemCalendarQuery.occurrences(
            in: interval,
            store: store,
            hiddenCalendarIDs: hiddenCalendarIDs
        )
    }
}

struct SystemCalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
}

struct SystemCalendarSourceGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let calendars: [SystemCalendarInfo]
}
