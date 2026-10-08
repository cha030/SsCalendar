import EventKit
import Foundation
import SwiftUI

/// 앱과 위젯이 공유하는 시스템 캘린더(EventKit) 설정 읽기·조회·필터 규칙.
/// 위젯 폴더에 심볼릭 링크로 공유한다. UI, 권한 요청, Observation은 포함하지 않는다.
///
/// 규칙:
/// - 연동 ON(`isEnabledKey`)이고 Full Access일 때만 조회한다.
/// - 숨긴 캘린더(`hiddenCalendarIDsKey`)는 조회 대상에서 제외하며, 모두 숨기면 빈 결과다.
/// - 일정은 복사·동기화하지 않고 요청한 범위만 조회해 표시 모델로 변환한다.
@MainActor
enum SystemCalendarQuery {
    // MARK: - App Group 설정 키

    static let isEnabledKey = "systemCalendarDisplayEnabled"
    static let hiddenCalendarIDsKey = "systemCalendarHiddenCalendarIdentifiers"
    static let selectionIntroShownKey = "systemCalendarSelectionIntroShown"

    /// 시스템 캘린더 설정이 저장되는 App Group 저장소.
    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: SharedModelContainer.appGroupIdentifier)
    }

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: isEnabledKey)
    }

    static func hiddenCalendarIDs(in defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: hiddenCalendarIDsKey) ?? [])
    }

    static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: - 조회

    /// 위젯용 조회 결과. 위젯은 색상을 직접 직렬화해야 하므로 원본 캘린더 CGColor를 함께 전달한다.
    struct Result {
        let occurrence: CalendarDisplayOccurrence
        let calendarColor: CGColor?
    }

    /// 저장된 설정(연동 ON/OFF, 숨긴 캘린더)과 현재 권한을 모두 적용해 조회한다.
    /// 위젯처럼 화면 상태 없이 설정만으로 판단해야 하는 곳에서 사용한다.
    static func enabledResults(
        in interval: DateInterval,
        defaults: UserDefaults,
        store: EKEventStore = EKEventStore()
    ) -> [Result] {
        guard isEnabled(in: defaults), hasFullAccess else { return [] }

        return visibleEvents(
            in: interval,
            store: store,
            hiddenCalendarIDs: hiddenCalendarIDs(in: defaults)
        )
        .map { Result(occurrence: displayOccurrence(for: $0), calendarColor: $0.calendar?.cgColor) }
    }

    /// 지정한 범위와 겹치는 시스템 일정을 표시 모델로 반환한다.
    /// 권한 확인은 호출하는 쪽에서 한다. 표시 대상 캘린더가 하나도 없으면 빈 배열.
    static func occurrences(
        in interval: DateInterval,
        store: EKEventStore,
        hiddenCalendarIDs: Set<String>
    ) -> [CalendarDisplayOccurrence] {
        visibleEvents(in: interval, store: store, hiddenCalendarIDs: hiddenCalendarIDs)
            .map(displayOccurrence(for:))
    }

    /// 앱과 위젯이 공유하는 단일 필터 경로: 숨기지 않은 캘린더만, 요청 범위만 조회한다.
    private static func visibleEvents(
        in interval: DateInterval,
        store: EKEventStore,
        hiddenCalendarIDs: Set<String>
    ) -> [EKEvent] {
        guard interval.duration > 0 else { return [] }

        // 사용자가 OFF로 선택한 캘린더는 조회 대상에서 제외한다(일정 단위로 거르지 않는다).
        let visibleCalendars = store.calendars(for: .event).filter {
            !hiddenCalendarIDs.contains($0.calendarIdentifier)
        }
        // calendars에 빈 배열을 넘기는 동작에 기대지 않고, 모두 OFF면 직접 빈 결과를 반환한다.
        guard !visibleCalendars.isEmpty else { return [] }

        let predicate = store.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: visibleCalendars
        )

        return store.events(matching: predicate)
    }

    static func displayOccurrence(for event: EKEvent) -> CalendarDisplayOccurrence {
        // 반복 일정의 각 발생분은 eventIdentifier를 공유하므로 시작 시각을 함께 사용한다.
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let calendarTitle = event.calendar?.title ?? ""
        let color = event.calendar?.cgColor.map { Color(cgColor: $0) } ?? .gray
        let eventStartDate = event.startDate ?? Date()
        let eventEndDate = event.endDate ?? eventStartDate
        // EventKit의 종일 일정 endDate는 종료일 다음 날 00:00인 exclusive 경계다.
        // 표시 모델은 종일 종료일을 inclusive로 다루므로 마지막 표시 시각으로 보정한다.
        let displayEndDate = event.isAllDay
            ? eventEndDate.addingTimeInterval(-1)
            : eventEndDate

        return CalendarDisplayOccurrence(
            id: "system:\(identifier):\(eventStartDate.timeIntervalSince1970)",
            source: .system(calendarTitle: calendarTitle),
            title: event.title ?? "",
            isAllDay: event.isAllDay,
            startDate: eventStartDate,
            endDate: displayEndDate,
            color: color
        )
    }
}
