import EventKit
import Foundation
import SwiftData

/// 외부(EventKit) 일정의 D-Day 설정을 SsCalendar 로컬에 별도 저장하는 모델(Step 5-2).
/// 외부 캘린더 원본(EKEvent)은 절대 수정하지 않는다 — 이 모델은 "참조 정보 + 켬/끔"만 가진다.
///
/// `SystemCalendarEventReference`를 그대로 저장하지 않고 필드를 풀어서 저장한다(SwiftData가
/// 평면 값 타입을 직접 저장하지 못하므로). EventKit 식별자는 캘린더 이동 등으로 바뀔 수 있다는
/// 전제 아래, 여러 식별자를 함께 보관해 `SystemCalendarWriteSupport.isSameItem`과 같은 우선순위로
/// 다시 찾는다(아래 `SystemCalendarEventReference.matchesSeries(of:)` 참고).
///
/// 반복 일정 D-Day 정책(확정, Step 5-2 반복 보완): D-Day는 발생분이 아니라 "시리즈(캘린더 항목)"
/// 단위로 켜고 끈다 — 한 번 켜면 이후 모든 회차에 그대로 적용된다. `occurrenceStartDate`/
/// `occurrenceDate`는 설정을 만든 시점의 발생 시각을 참고용으로만 남겨 두는 값이고, 매칭(같은
/// 설정인지 판단)에는 더 이상 쓰지 않는다 — 과거(이번 보완 이전) 버전은 발생분 단위로 매칭했었다.
@Model
final class ExternalEventDDaySetting {
    @Attribute(.unique) var id: String
    var eventIdentifier: String?
    var calendarItemIdentifier: String
    var externalIdentifier: String?
    var calendarIdentifier: String?
    /// 설정을 저장할 당시 조회된 발생분의 시작 시각. D-Day 계산은 이 값을 기준으로 한다.
    var occurrenceStartDate: Date
    var occurrenceDate: Date?
    var isRecurring: Bool
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        eventIdentifier: String?,
        calendarItemIdentifier: String,
        externalIdentifier: String?,
        calendarIdentifier: String?,
        occurrenceStartDate: Date,
        occurrenceDate: Date?,
        isRecurring: Bool,
        isEnabled: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.eventIdentifier = eventIdentifier
        self.calendarItemIdentifier = calendarItemIdentifier
        self.externalIdentifier = externalIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.occurrenceStartDate = occurrenceStartDate
        self.occurrenceDate = occurrenceDate
        self.isRecurring = isRecurring
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    /// 조회 시 재구성한 참조. `SystemCalendarEventReference`와 같은 모양으로 비교할 때 쓴다.
    var reference: SystemCalendarEventReference {
        SystemCalendarEventReference(
            eventIdentifier: eventIdentifier,
            calendarItemIdentifier: calendarItemIdentifier,
            externalIdentifier: externalIdentifier,
            calendarIdentifier: calendarIdentifier,
            startDate: occurrenceStartDate,
            occurrenceDate: occurrenceDate,
            isRecurring: isRecurring
        )
    }
}

extension SystemCalendarEventReference {
    /// `SystemCalendarWriteSupport.isSameItem(_:as:)`과 같은 식별자 우선순위(eventIdentifier →
    /// calendarItemIdentifier → externalIdentifier)로 "같은 캘린더 항목(시리즈)"인지만 비교한다.
    /// 발생 시각은 보지 않는다 — 반복 시리즈의 서로 다른 회차라도 시리즈가 같으면 true다.
    private func matchesCalendarItem(
        eventIdentifier: String?,
        calendarItemIdentifier: String,
        externalIdentifier: String?
    ) -> Bool {
        if let mine = self.eventIdentifier, let theirs = eventIdentifier, mine == theirs {
            return true
        }
        if self.calendarItemIdentifier == calendarItemIdentifier {
            return true
        }
        if let mine = self.externalIdentifier, !mine.isEmpty,
           let theirs = externalIdentifier, mine == theirs {
            return true
        }
        return false
    }

    /// 다른 reference와 같은 시리즈(캘린더 항목)인지. D-Day 설정을 저장된 reference끼리 매칭할 때 쓴다.
    func matchesSeries(of other: SystemCalendarEventReference) -> Bool {
        matchesCalendarItem(
            eventIdentifier: other.eventIdentifier,
            calendarItemIdentifier: other.calendarItemIdentifier,
            externalIdentifier: other.externalIdentifier
        )
    }

    /// 실제 EKEvent와 같은 시리즈인지. 다음 발생일 조회(SystemCalendarQuery.nextOccurrence) 등
    /// EventKit에서 막 읽어온 이벤트와 저장된 설정을 맞춰볼 때 쓴다.
    func matchesSeries(of event: EKEvent) -> Bool {
        matchesCalendarItem(
            eventIdentifier: event.eventIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier
        )
    }
}

/// 외부 일정 D-Day 설정의 조회·켬끔(upsert)을 담당한다. 같은 시리즈를 중복 생성하지 않는다.
///
/// 안전한 전환(과거 발생분 단위 데이터 호환): 이전 버전은 발생분 단위로 설정을 저장했으므로,
/// 같은 시리즈에 발생 시각이 다른 레코드가 여러 개 남아 있을 수 있다. 그 데이터를 지우거나
/// 하나로 합쳐 쓰지 않고(값이 서로 다르면 어느 쪽이 "맞는" 의도인지 알 수 없다), 대신:
/// - 읽을 때는 매칭되는 레코드 중 하나라도 켜져 있으면 켜진 것으로 본다(사용자가 과거에 켠 D-Day를
///   실수로 꺼진 것처럼 보이게 하지 않기 위함 — "지난 일정 D-Day를 강제로 OFF하지 않는다"는 기존
///   원칙과 같은 방향).
/// - 쓸 때는 매칭되는 레코드를 전부 같은 값으로 맞춘다. 레코드를 삭제하지는 않으므로, 여러 번
///   토글하다 보면 자연히 값이 수렴한다(완료 보고에 이 동작을 별도로 알렸다).
@MainActor
enum ExternalDDayStore {
    static func matchingSettings(
        for reference: SystemCalendarEventReference,
        in settings: [ExternalEventDDaySetting]
    ) -> [ExternalEventDDaySetting] {
        settings.filter { $0.reference.matchesSeries(of: reference) }
    }

    static func isEnabled(
        for reference: SystemCalendarEventReference,
        in settings: [ExternalEventDDaySetting]
    ) -> Bool {
        matchingSettings(for: reference, in: settings).contains { $0.isEnabled }
    }

    /// 매칭되는 기존 설정이 있으면(과거 발생분 단위로 여러 개 남아 있을 수 있다) 전부 같은 값으로
    /// 맞추고, 없으면 정확히 하나만 새로 만든다(중복 생성 방지).
    @discardableResult
    static func setEnabled(
        _ isEnabled: Bool,
        for reference: SystemCalendarEventReference,
        existingSettings: [ExternalEventDDaySetting],
        context: ModelContext
    ) -> ExternalEventDDaySetting {
        let matches = matchingSettings(for: reference, in: existingSettings)

        if let first = matches.first {
            for setting in matches {
                setting.isEnabled = isEnabled
            }
            return first
        }

        let created = ExternalEventDDaySetting(
            eventIdentifier: reference.eventIdentifier,
            calendarItemIdentifier: reference.calendarItemIdentifier,
            externalIdentifier: reference.externalIdentifier,
            calendarIdentifier: reference.calendarIdentifier,
            occurrenceStartDate: reference.startDate,
            occurrenceDate: reference.occurrenceDate,
            isRecurring: reference.isRecurring,
            isEnabled: isEnabled
        )
        context.insert(created)
        return created
    }
}
