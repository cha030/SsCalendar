import EventKit
import Foundation
import Observation
import SwiftUI

/// iOS 시스템 캘린더(EventKit) 서비스. 일정 수정·삭제는 Apple 일정 화면(EKEventViewController)이 수행한다.
/// 일정은 복사·동기화하지 않고, 화면이 요청한 날짜 범위만 그때그때 조회해 표시 모델로 변환한다.
@MainActor
@Observable
final class SystemCalendarService {
    static let shared = SystemCalendarService()

    /// 외부 일정 상세·편집·삭제와 새 일정의 외부 캘린더 저장을 임시로 비활성화한다.
    /// 조회·위젯 연동은 유지하며, 외부 EventKit 화면을 다시 허용할 때 이 플래그만 되돌린다.
    static let isExternalEventAccessEnabled = false

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
    /// 새 일정의 기본 저장 위치(App Group UserDefaults). 값이 없으면 SsCalendar 로컬이다.
    private static let defaultSaveDestinationKey = "eventDefaultSaveDestination"

    /// 시스템 캘린더 데이터나 권한이 바뀔 때마다 증가한다. 화면은 이 값을 조회 트리거로 사용한다.
    private(set) var changeToken = 0
    private(set) var authorizationStatus: EKAuthorizationStatus
    private(set) var hiddenCalendarIDs: Set<String>
    /// 사용자가 고른 기본 저장 위치(저장된 값 그대로). 실제로 쓸 수 있는지는 `effectiveDefaultSaveDestination`으로 판단한다.
    private(set) var storedDefaultSaveDestination: EventSaveDestination

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let sharedDefaults = SystemCalendarService.settingsStore
    @ObservationIgnored private var changeObservation: Task<Void, Never>?
    @ObservationIgnored private var activationRefreshTask: Task<Void, Never>?

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        hiddenCalendarIDs = SystemCalendarQuery.hiddenCalendarIDs(in: sharedDefaults)
        storedDefaultSaveDestination = sharedDefaults
            .string(forKey: Self.defaultSaveDestinationKey)
            .flatMap(EventSaveDestination.init(rawValue:)) ?? .local
        changeObservation = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: .EKEventStoreChanged)
                .map { $0.name }
            for await _ in changes {
                // 계정 제거·캘린더 삭제도 이 알림으로 전달된다. 권한 상태도 함께 다시 확인한다.
                self?.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
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

        activationRefreshTask?.cancel()
        activationRefreshTask = Task { [weak self] in
            // 앱 활성화 직후 EventKit의 외부 소스 반영이 끝날 시간을 비동기로 양보한다.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else {
                return
            }

            // 백그라운드 동안 바뀐 외부 일정의 오래된 EventKit 캐시를 버린 뒤 다시 동기화한다.
            // refreshSourcesIfNecessary()는 원격 변경을 반영하면서도
            // 이미 전달된 EKEvent 객체를 무효화하지 않는다.
            self.store.refreshSourcesIfNecessary()
            self.changeToken += 1
            WidgetReloadManager.requestCalendarReload()
        }
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
                    title: calendars.first?.source?.title ?? String(localized: "기타"),
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

    // MARK: - 쓰기 기반 (Phase 2)

    /// 연동 ON이고 Full Access일 때만 시스템 캘린더에 쓸 수 있다. 연동 OFF면 로컬 저장만 제공한다.
    private func ensureWritableAccess() throws(SystemCalendarAccessError) {
        guard SystemCalendarQuery.isEnabled(in: sharedDefaults) else { throw .integrationDisabled }
        guard hasFullAccess else { throw .accessDenied }
    }

    var canWriteToSystemCalendars: Bool {
        (try? ensureWritableAccess()) != nil
    }

    /// 새 일정 저장 위치로 고를 수 있는 시스템 캘린더 목록. 쓸 수 없는 상태면 빈 배열.
    func writableCalendarGroups() -> [SystemWritableCalendarSourceGroup] {
        // 계정 추가·제거(EKEventStoreChanged) 시 다시 그려지도록 추적한다.
        _ = changeToken
        guard canWriteToSystemCalendars else { return [] }

        return SystemCalendarWriteSupport.writableCalendarGroups(
            in: store,
            hiddenCalendarIDs: hiddenCalendarIDs
        )
    }

    /// 저장 직전 검증. 로컬은 항상 통과하고, 시스템 캘린더는 쓸 수 없으면 오류를 던진다.
    /// 실패 시 다른 캘린더나 로컬로 대신 저장하지 않는다.
    func validateSaveDestination(_ destination: EventSaveDestination) throws(SystemCalendarAccessError) {
        guard case .systemCalendar(let calendarIdentifier) = destination else { return }
        try ensureWritableAccess()
        _ = try SystemCalendarWriteSupport.validatedCalendar(
            withIdentifier: calendarIdentifier,
            in: store
        )
        guard isCalendarVisible(calendarIdentifier) else { throw .calendarHidden }
    }

    /// 새 일정을 시스템 캘린더에 저장한다. SwiftData에는 복사하지 않는다.
    /// 저장 직전에 권한·캘린더 상태를 다시 확인하며, 실패해도 다른 캘린더나 로컬로 대신 저장하지 않는다.
    func saveNewEvent(
        _ draft: SystemEventDraft,
        toCalendarWithIdentifier calendarIdentifier: String
    ) throws(SystemCalendarAccessError) {
        // 편집 중 계정이 제거되었을 수 있으므로 저장소의 최신 캘린더 목록으로 확인한다.
        try validateSaveDestination(.systemCalendar(calendarIdentifier: calendarIdentifier))
        let targetCalendar = try SystemCalendarWriteSupport.validatedCalendar(
            withIdentifier: calendarIdentifier,
            in: store
        )

        let event = EKEvent(eventStore: store)
        SystemCalendarWriteSupport.apply(draft, to: event, in: targetCalendar)

        do {
            // 새 반복 일정은 시리즈 전체(규칙 포함)를 저장해야 하므로 futureEvents를 사용한다.
            try store.save(
                event,
                span: draft.repeatRule == nil ? .thisEvent : .futureEvents,
                commit: true
            )
        } catch {
            throw .saveFailed
        }

        reloadAfterSystemEventChange()
    }

    /// 저장된 기본 저장 위치를 지금 쓸 수 없는 이유. 쓸 수 있거나 로컬이면 nil.
    var defaultSaveDestinationIssue: SystemCalendarAccessError? {
        _ = changeToken
        do {
            try validateSaveDestination(storedDefaultSaveDestination)
            return nil
        } catch {
            return error
        }
    }

    /// 새 일정 편집기의 초기 저장 위치. 저장된 기본값을 쓸 수 없으면(연동 OFF, 권한 거부, 계정 제거 등) 로컬이다.
    /// 저장된 값은 지우지 않으므로 계정·권한이 돌아오면 다시 사용된다.
    var effectiveDefaultSaveDestination: EventSaveDestination {
        defaultSaveDestinationIssue == nil ? storedDefaultSaveDestination : .local
    }

    /// 기본 저장 위치를 바꾼다. 지금 쓸 수 없는 시스템 캘린더는 기본값으로 저장하지 않는다.
    func setDefaultSaveDestination(_ destination: EventSaveDestination) throws(SystemCalendarAccessError) {
        try validateSaveDestination(destination)
        storedDefaultSaveDestination = destination
        sharedDefaults.set(destination.rawValue, forKey: Self.defaultSaveDestinationKey)
    }

    /// 표시 중인 시스템 일정 발생분의 원본 EKEvent를 다시 조회한다(EKEventViewController 표시용).
    /// 조회만 하며 일정을 변경하지 않는다.
    func event(for reference: SystemCalendarEventReference) throws(SystemCalendarAccessError) -> EKEvent {
        // 연동 OFF면 시스템 일정이 표시되지 않으므로 열 수도 없다.
        guard SystemCalendarQuery.isEnabled(in: sharedDefaults) else { throw .integrationDisabled }
        guard hasFullAccess else { throw .accessDenied }

        do {
            return try SystemCalendarWriteSupport.event(for: reference, in: store)
        } catch .eventNotFound {
            // 공유 store의 reset()은 그 store에서 얻은 모든 EKEvent를 무효화하므로,
            // 현재 상세 화면이나 다른 화면의 참조를 깨뜨릴 수 있다. 실패한 조회만
            // 독립된 저장소에서 원격 갱신 후 동일 식별자·발생 시각으로 한 번 재조회한다.
            let retryStore = EKEventStore()
            retryStore.refreshSourcesIfNecessary()
            return try SystemCalendarWriteSupport.event(for: reference, in: retryStore)
        }
    }

    /// Apple 일정 화면에서 수정·삭제를 허용할지 여부. 읽기 전용 캘린더의 일정은 보기만 허용한다.
    func canModify(_ event: EKEvent) -> Bool {
        canWriteToSystemCalendars && (event.calendar.map(SystemCalendarWriteSupport.isWritable) ?? false)
    }

    /// Apple 일정 화면이 닫힌 뒤 호출한다. EKEventStoreChanged 알림이 늦게 와도 화면과 위젯을 바로 갱신한다.
    func reloadAfterSystemEventChange() {
        changeToken += 1
        WidgetReloadManager.requestCalendarReload()
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
