import Foundation
import SwiftData

/// 반복 일정의 특정 발생분만 수정하거나 삭제하기 위한 예외 레코드(Step 5-2 개별 수정·삭제).
/// 원본 반복 Event는 그대로 둔 채 이 레코드로 "그 발생분만" 다르게 표시한다. SsCalendar 자체
/// 일정에만 적용하며, 외부 EventKit 반복 일정의 편집 동작은 건드리지 않는다.
@Model
final class EventOccurrenceException {
    @Attribute(.unique) var id: UUID
    /// 원본 반복 Event.id. ExternalEventDDaySetting과 같은 방식의 느슨한 참조로 두고(관계가
    /// 아님), Event를 삭제할 때 이 레코드도 함께 정리한다(EventEditorView.deleteEvent 참고).
    var eventID: UUID
    /// 이 예외가 적용되는 "원래" 발생 시작 시각(override 이전, 반복 규칙이 그대로 계산한 값).
    /// 예외를 찾는 키는 항상 이 값이며, override로 날짜를 옮겨도 이 값 자체는 바뀌지 않는다.
    var originalOccurrenceStartDate: Date
    /// true면 이 발생분은 완전히 제외된다(개별 삭제). 이때는 아래 override 필드를 쓰지 않는다.
    var isExcluded: Bool

    // 개별 수정(override) 스냅샷. 일부 필드만 옵셔널로 두면 "수정 안 함"과 "비워서 수정함"을
    // 구분할 수 없으므로, 수정 시 편집 화면에 보이는 값을 한 번에 전부 저장한다(isExcluded가
    // false일 때만 의미가 있다).
    var overrideTitle: String
    var overrideIsAllDay: Bool
    var overrideStartDate: Date
    var overrideEndDate: Date
    var overrideColor: String
    var overrideAlarmOption: String
    var overrideAlarmTimeIntervalBeforeStart: TimeInterval?
    var overrideAlarmCustomValue: Int
    var overrideAlarmCustomUnit: String
    var overrideMemo: String

    init(
        id: UUID = UUID(),
        eventID: UUID,
        originalOccurrenceStartDate: Date,
        isExcluded: Bool,
        overrideTitle: String = "",
        overrideIsAllDay: Bool = false,
        overrideStartDate: Date = Date(),
        overrideEndDate: Date = Date(),
        overrideColor: String = "파란색",
        overrideAlarmOption: String = "없음",
        overrideAlarmTimeIntervalBeforeStart: TimeInterval? = nil,
        overrideAlarmCustomValue: Int = 1,
        overrideAlarmCustomUnit: String = "일",
        overrideMemo: String = ""
    ) {
        self.id = id
        self.eventID = eventID
        self.originalOccurrenceStartDate = originalOccurrenceStartDate
        self.isExcluded = isExcluded
        self.overrideTitle = overrideTitle
        self.overrideIsAllDay = overrideIsAllDay
        self.overrideStartDate = overrideStartDate
        self.overrideEndDate = overrideEndDate
        self.overrideColor = overrideColor
        self.overrideAlarmOption = overrideAlarmOption
        self.overrideAlarmTimeIntervalBeforeStart = overrideAlarmTimeIntervalBeforeStart
        self.overrideAlarmCustomValue = overrideAlarmCustomValue
        self.overrideAlarmCustomUnit = overrideAlarmCustomUnit
        self.overrideMemo = overrideMemo
    }
}
