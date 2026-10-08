import EventKit
import Foundation
import SwiftUI

// 앱 전용: 시스템 캘린더 쓰기(Phase 2)를 위한 기반 타입과 조회 규칙.
// 이 파일은 외부 데이터를 직접 저장하지 않는다. 저장(commit)은 SystemCalendarService에서 한다.
//
// 규칙:
// - 연동 OFF 또는 Full Access가 아니면 시스템 캘린더는 저장 위치가 될 수 없다(로컬만 제공).
// - 저장 시점 검증(`validatedCalendar`)은 실패를 그대로 알리며, 다른 캘린더로 대신 저장하지 않는다.
// - 기본 저장 위치는 SsCalendar 로컬이며, 저장된 기본값을 쓸 수 없으면 편집기 초기 선택만 로컬로 보여준다.
// - 표시 OFF로 설정한 캘린더는 저장 위치로 사용하지 않는다(목록 제외, 저장 시 오류).

/// 새 일정을 저장할 위치.
enum EventSaveDestination: Hashable {
    /// SsCalendar(SwiftData) 로컬 저장. 기본값.
    case local
    /// 쓰기 가능한 iOS 시스템 캘린더(iCloud·Google 등). calendarIdentifier로 식별한다.
    case systemCalendar(calendarIdentifier: String)

    private static let localRawValue = "local"
    private static let systemPrefix = "system:"

    /// App Group UserDefaults 저장용 문자열 표현.
    var rawValue: String {
        switch self {
        case .local:
            return Self.localRawValue
        case .systemCalendar(let calendarIdentifier):
            return Self.systemPrefix + calendarIdentifier
        }
    }

    /// 알 수 없는 값은 nil을 반환한다. 호출하는 쪽에서 기본값(.local)을 사용한다.
    init?(rawValue: String) {
        if rawValue == Self.localRawValue {
            self = .local
        } else if rawValue.hasPrefix(Self.systemPrefix) {
            let calendarIdentifier = String(rawValue.dropFirst(Self.systemPrefix.count))
            guard !calendarIdentifier.isEmpty else { return nil }
            self = .systemCalendar(calendarIdentifier: calendarIdentifier)
        } else {
            return nil
        }
    }
}

/// 시스템 캘린더를 쓰기 대상으로 사용할 수 없는 이유. 자동 대체 저장 없이 사용자에게 그대로 안내한다.
enum SystemCalendarAccessError: Error, Equatable {
    /// 설정에서 iPhone 캘린더 연동이 꺼져 있다.
    case integrationDisabled
    /// 캘린더 Full Access 권한이 없다(거부·제한·미결정·쓰기 전용).
    case accessDenied
    /// 캘린더가 없다. 계정 제거, 캘린더 삭제 등.
    case calendarNotFound
    /// 구독·생일 캘린더처럼 수정할 수 없는 캘린더다.
    case calendarReadOnly
    /// "표시할 캘린더 선택"에서 꺼 둔 캘린더다. 저장해도 화면에 보이지 않으므로 저장 위치로 쓰지 않는다.
    case calendarHidden
    /// 원본 일정이나 해당 발생분을 찾을 수 없다. 다른 기기에서 삭제·이동된 경우 등.
    case eventNotFound
    /// EventKit 저장 자체가 실패했다.
    case saveFailed

    var message: String {
        switch self {
        case .integrationDisabled:
            return "iPhone 캘린더 연동이 꺼져 있습니다."
        case .accessDenied:
            return "캘린더 접근 권한이 없습니다. 설정 앱에서 권한을 허용해 주세요."
        case .calendarNotFound:
            return "선택한 캘린더를 찾을 수 없습니다. 계정이 제거되었거나 캘린더가 삭제되었을 수 있습니다."
        case .calendarReadOnly:
            return "이 캘린더는 수정할 수 없습니다."
        case .calendarHidden:
            return "선택한 캘린더가 '표시할 캘린더 선택'에서 꺼져 있습니다."
        case .eventNotFound:
            return "일정을 찾을 수 없습니다. 다른 기기에서 삭제되었거나 변경되었을 수 있습니다."
        case .saveFailed:
            return "캘린더에 일정을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요."
        }
    }
}

/// 저장 위치 선택 화면용 쓰기 가능한 캘린더 정보.
struct SystemWritableCalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
    /// 시스템의 "새 일정 기본 캘린더"인지 여부.
    let isSystemDefault: Bool
}

/// 새 시스템 일정에 저장할 입력값. EventEditorView의 입력을 EventKit 규칙과 무관한 값으로 옮긴 것이다.
struct SystemEventDraft {
    enum RepeatFrequency {
        case daily
        case weekly
        case monthly
        case yearly
    }

    let title: String
    let isAllDay: Bool
    /// 종일 일정이면 날짜 부분만 사용한다. 종료일은 화면과 같이 inclusive(마지막 날)다.
    let startDate: Date
    let endDate: Date
    let notes: String
    /// 시작 시각 기준 몇 초 전에 알릴지. nil이면 알림 없음.
    let alarmOffsetBeforeStart: TimeInterval?
    /// nil이면 반복 안 함. 반복 종료는 기존 로컬 일정과 같이 두지 않는다.
    let repeatRule: (frequency: RepeatFrequency, interval: Int)?
}

struct SystemWritableCalendarSourceGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let calendars: [SystemWritableCalendarInfo]
}

/// EventKit 저장소에 대한 쓰기 기반 조회 규칙. 권한·연동 확인은 SystemCalendarService에서 한다.
@MainActor
enum SystemCalendarWriteSupport {
    /// 새 일정을 추가할 수 있는 캘린더인지 판단한다.
    static func isWritable(_ calendar: EKCalendar) -> Bool {
        guard calendar.allowsContentModifications, !calendar.isImmutable else { return false }
        // 구독·생일 캘린더는 위 값이 false지만, 계정 종류와 무관하게 확실히 제외한다.
        return calendar.type != .subscription && calendar.type != .birthday
    }

    static func writableCalendars(in store: EKEventStore) -> [EKCalendar] {
        store.calendars(for: .event).filter(isWritable)
    }

    /// 계정(source)별로 묶은 쓰기 가능한 캘린더 목록. 표시 OFF로 설정한 캘린더는 제외한다.
    static func writableCalendarGroups(
        in store: EKEventStore,
        hiddenCalendarIDs: Set<String>
    ) -> [SystemWritableCalendarSourceGroup] {
        let systemDefaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        let visibleWritableCalendars = writableCalendars(in: store).filter {
            !hiddenCalendarIDs.contains($0.calendarIdentifier)
        }
        let calendarsBySource = Dictionary(grouping: visibleWritableCalendars) {
            $0.source?.sourceIdentifier ?? ""
        }

        return calendarsBySource
            .map { sourceID, calendars in
                SystemWritableCalendarSourceGroup(
                    id: sourceID,
                    title: calendars.first?.source?.title ?? "기타",
                    calendars: calendars
                        .map { calendar in
                            SystemWritableCalendarInfo(
                                id: calendar.calendarIdentifier,
                                title: calendar.title,
                                color: calendar.cgColor.map { Color(cgColor: $0) } ?? .gray,
                                isSystemDefault: calendar.calendarIdentifier == systemDefaultID
                            )
                        }
                        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// 저장 직전에 사용할 캘린더를 확인한다. 실패하면 오류를 던지며 다른 캘린더로 대체하지 않는다.
    static func validatedCalendar(
        withIdentifier calendarIdentifier: String,
        in store: EKEventStore
    ) throws(SystemCalendarAccessError) -> EKCalendar {
        guard let calendar = store.calendar(withIdentifier: calendarIdentifier) else {
            throw .calendarNotFound
        }
        guard isWritable(calendar) else {
            throw .calendarReadOnly
        }
        return calendar
    }

    // MARK: - 새 일정 변환

    /// 입력값을 EventKit 규칙에 맞춰 EKEvent에 옮긴다. 저장(commit)은 호출하는 쪽에서 한다.
    /// 색상은 지정하지 않는다. 시스템 일정은 항상 원본 캘린더 색으로 표시된다.
    static func apply(
        _ draft: SystemEventDraft,
        to event: EKEvent,
        in targetCalendar: EKCalendar,
        calendar: Calendar = .current
    ) {
        event.calendar = targetCalendar
        event.title = draft.title
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        event.isAllDay = draft.isAllDay

        if draft.isAllDay {
            // Apple 캘린더는 종일 일정의 endDate를 마지막 날 23:59:59로 저장한다(실측).
            // 다음 날 00:00을 넘기면 EventKit이 그날까지 포함해 하루가 늘어나므로 같은 값으로 맞춘다.
            let firstDay = calendar.startOfDay(for: draft.startDate)
            let lastDay = max(firstDay, calendar.startOfDay(for: draft.endDate))
            let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            event.startDate = firstDay
            event.endDate = calendar.date(byAdding: .second, value: -1, to: nextDay) ?? lastDay
        } else {
            event.startDate = draft.startDate
            event.endDate = draft.endDate
        }

        // 알림은 EKAlarm으로 저장하며 SsCalendar 로컬 알림(NotificationManager)은 사용하지 않는다.
        // 종일 일정의 상대 알림은 EventKit 규칙에 따라 그날 00:00을 기준으로 계산된다.
        event.alarms = draft.alarmOffsetBeforeStart.map {
            [EKAlarm(relativeOffset: -max(0, $0))]
        }

        // 요일·날짜를 지정하지 않으면 EventKit은 시작일의 요일·날짜·월을 기준으로 반복한다.
        // 31일·2월 29일처럼 없는 날짜는 건너뛰어 기존 로컬 반복 엔진과 같은 결과가 된다.
        event.recurrenceRules = draft.repeatRule.map { rule in
            [EKRecurrenceRule(
                recurrenceWith: rule.frequency.ekFrequency,
                interval: max(1, rule.interval),
                end: nil
            )]
        }
    }

    // MARK: - 발생분 재조회

    /// 표시 모델의 참조로 원본 EKEvent 발생분을 다시 조회한다(EKEventViewController 표시용).
    ///
    /// `event(withIdentifier:)`는 반복 일정의 첫 발생분만 반환하므로, 발생 시각 주변을 날짜 범위로
    /// 다시 조회한 뒤 식별자와 발생 시각이 모두 맞는 발생분을 고른다.
    static func event(
        for reference: SystemCalendarEventReference,
        in store: EKEventStore,
        calendar: Calendar = .current
    ) throws(SystemCalendarAccessError) -> EKEvent {
        if let event = matchingOccurrence(for: reference, in: store, calendar: calendar) {
            return event
        }

        // 반복이 아닌 일정은 다른 기기에서 시각이 바뀌어 조회 범위를 벗어났을 수 있다.
        // 반복 일정은 첫 발생분이 반환되어 다른 날짜를 열게 되므로 이 경로를 사용하지 않는다.
        if !reference.isRecurring,
           let event = singleEvent(for: reference, in: store),
           !event.hasRecurrenceRules {
            return event
        }

        throw .eventNotFound
    }

    private static func matchingOccurrence(
        for reference: SystemCalendarEventReference,
        in store: EKEventStore,
        calendar: Calendar
    ) -> EKEvent? {
        let anchorDates = [reference.startDate, reference.occurrenceDate].compactMap { $0 }
        guard
            let earliest = anchorDates.min(),
            let latest = anchorDates.max(),
            let searchStart = calendar.date(byAdding: .day, value: -1, to: earliest),
            let searchEnd = calendar.date(byAdding: .day, value: 1, to: latest)
        else {
            return nil
        }

        // 일정이 다른 캘린더로 옮겨졌을 수 있으므로 모든 캘린더(숨긴 캘린더 포함)에서 찾는다.
        let predicate = store.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: nil
        )
        let candidates = store.events(matching: predicate).filter {
            isSameItem($0, as: reference)
        }

        // 원래 발생 시각은 개별 발생분을 옮겨도 변하지 않으므로 우선 비교하고, 다음으로 시작 시각을 비교한다.
        if let occurrenceDate = reference.occurrenceDate,
           let event = candidates.first(where: { $0.occurrenceDate == occurrenceDate }) {
            return event
        }
        if let event = candidates.first(where: { $0.startDate == reference.startDate }) {
            return event
        }
        // 반복이 아닌 일정은 해당 일정이 하나뿐이므로 시각이 조금 바뀌었어도 같은 일정이다.
        if !reference.isRecurring, candidates.count == 1, let event = candidates.first,
           !event.hasRecurrenceRules {
            return event
        }
        return nil
    }

    private static func isSameItem(_ event: EKEvent, as reference: SystemCalendarEventReference) -> Bool {
        if let eventIdentifier = reference.eventIdentifier,
           event.eventIdentifier == eventIdentifier {
            return true
        }
        if event.calendarItemIdentifier == reference.calendarItemIdentifier {
            return true
        }
        if let externalIdentifier = reference.externalIdentifier, !externalIdentifier.isEmpty {
            return event.calendarItemExternalIdentifier == externalIdentifier
        }
        return false
    }

    private static func singleEvent(
        for reference: SystemCalendarEventReference,
        in store: EKEventStore
    ) -> EKEvent? {
        if let eventIdentifier = reference.eventIdentifier,
           let event = store.event(withIdentifier: eventIdentifier) {
            return event
        }
        return store.calendarItem(withIdentifier: reference.calendarItemIdentifier) as? EKEvent
    }
}

private extension SystemEventDraft.RepeatFrequency {
    var ekFrequency: EKRecurrenceFrequency {
        switch self {
        case .daily:
            return .daily
        case .weekly:
            return .weekly
        case .monthly:
            return .monthly
        case .yearly:
            return .yearly
        }
    }
}
