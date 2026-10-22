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

/// 전체 반복 일정 수정 시 기존 개별 수정 예외를 새 시리즈 값과 합치는 정책.
enum RecurringSeriesExceptionUpdatePolicy: Equatable {
    /// 실제로 개별 변경된 값은 유지하고, 기존 시리즈 값과 같던 필드만 새 시리즈 값을 따른다.
    case preserveIndividualChanges
    /// 이번 전체 편집에서 변경된 필드를 개별 수정 예외에도 적용한다.
    case applyChangedSeriesValues
}

/// 전체 반복 일정 저장 전에 필요한 사용자 상호작용을 순수 로직으로 판정한다.
nonisolated enum RecurringSeriesExceptionSaveRequirement: Equatable {
    case saveDirectly
    case chooseUpdatePolicy
    case blockUnsafeRecurrenceChange
}

/// Event와 개별 수정 예외가 공유하는 필드의 저장 전 스냅샷.
struct RecurringSeriesValues: Equatable {
    let title: String
    let isAllDay: Bool
    let startDate: Date
    let endDate: Date
    let color: String
    let alarmOption: String
    let alarmTimeIntervalBeforeStart: TimeInterval?
    let alarmCustomValue: Int
    let alarmCustomUnit: String
    let repeatUnit: String
    let repeatInterval: Int
    let memo: String

    init(event: Event) {
        title = event.title
        isAllDay = event.isAllDay
        startDate = event.startDate
        endDate = event.endDate
        color = event.color
        alarmOption = event.alarmOption
        alarmTimeIntervalBeforeStart = event.alarmTimeIntervalBeforeStart
        alarmCustomValue = event.alarmCustomValue
        alarmCustomUnit = event.alarmCustomUnit
        repeatUnit = event.repeatUnit
        repeatInterval = event.repeatInterval
        memo = event.memo
    }

    init(
        title: String,
        isAllDay: Bool,
        startDate: Date,
        endDate: Date,
        color: String,
        alarmOption: String,
        alarmTimeIntervalBeforeStart: TimeInterval?,
        alarmCustomValue: Int,
        alarmCustomUnit: String,
        repeatUnit: String,
        repeatInterval: Int,
        memo: String
    ) {
        self.title = title
        self.isAllDay = isAllDay
        self.startDate = startDate
        self.endDate = endDate
        self.color = color
        self.alarmOption = alarmOption
        self.alarmTimeIntervalBeforeStart = alarmTimeIntervalBeforeStart
        self.alarmCustomValue = alarmCustomValue
        self.alarmCustomUnit = alarmCustomUnit
        self.repeatUnit = repeatUnit
        self.repeatInterval = repeatInterval
        self.memo = memo
    }
}

/// 전체 반복 일정 수정과 기존 개별 예외를 데이터 손실 없이 결합한다.
enum RecurringSeriesExceptionUpdater {
    static func saveRequirement(
        exceptions: [EventOccurrenceException],
        oldValues: RecurringSeriesValues,
        newValues: RecurringSeriesValues
    ) -> RecurringSeriesExceptionSaveRequirement {
        guard !exceptions.isEmpty else { return .saveDirectly }

        let recurrenceRuleChanged =
            oldValues.repeatUnit != newValues.repeatUnit ||
            oldValues.repeatInterval != newValues.repeatInterval
        guard !recurrenceRuleChanged else { return .blockUnsafeRecurrenceChange }

        return exceptions.contains { !$0.isExcluded }
            ? .chooseUpdatePolicy
            : .saveDirectly
    }

    static func apply(
        from oldValues: RecurringSeriesValues,
        to newValues: RecurringSeriesValues,
        policy: RecurringSeriesExceptionUpdatePolicy,
        exceptions: [EventOccurrenceException]
    ) {
        let startDelta = newValues.isAllDay && oldValues.isAllDay
            ? AllDayDate.utcCalendar.dateComponents(
                [.day],
                from: AllDayDate.normalizedStorageDate(oldValues.startDate),
                to: AllDayDate.normalizedStorageDate(newValues.startDate)
            ).day ?? 0
            : nil
        let endDelta = newValues.isAllDay && oldValues.isAllDay
            ? AllDayDate.utcCalendar.dateComponents(
                [.day],
                from: AllDayDate.normalizedStorageDate(oldValues.endDate),
                to: AllDayDate.normalizedStorageDate(newValues.endDate)
            ).day ?? 0
            : nil
        let timedStartDelta = newValues.startDate.timeIntervalSince(oldValues.startDate)
        let timedEndDelta = newValues.endDate.timeIntervalSince(oldValues.endDate)
        let scheduleChanged = (startDelta ?? 0) != 0 ||
            (endDelta ?? 0) != 0 ||
            timedStartDelta != 0 ||
            timedEndDelta != 0

        for exception in exceptions {
            let oldOriginalStart = exception.originalOccurrenceStartDate
            if let startDelta {
                exception.originalOccurrenceStartDate = AllDayDate.adding(
                    .day,
                    value: startDelta,
                    toStorageDate: oldOriginalStart
                ) ?? oldOriginalStart
            } else {
                exception.originalOccurrenceStartDate = oldOriginalStart.addingTimeInterval(timedStartDelta)
            }

            // 개별 삭제는 항상 삭제 상태를 유지한다. 새 반복 시작점에 맞춰 식별 슬롯만 옮긴다.
            guard !exception.isExcluded else { continue }

            switch policy {
            case .preserveIndividualChanges:
                applyUnmodifiedSeriesFields(
                    from: oldValues,
                    to: newValues,
                    exception: exception
                )
                // 개별 시간 이동량을 보존하면서 시리즈의 날짜·시간 이동도 함께 적용한다.
                if exception.overrideIsAllDay {
                    exception.overrideStartDate = AllDayDate.adding(
                        .day,
                        value: startDelta ?? Int(timedStartDelta / 86_400),
                        toStorageDate: exception.overrideStartDate
                    ) ?? exception.overrideStartDate
                    exception.overrideEndDate = AllDayDate.adding(
                        .day,
                        value: endDelta ?? Int(timedEndDelta / 86_400),
                        toStorageDate: exception.overrideEndDate
                    ) ?? exception.overrideEndDate
                } else {
                    exception.overrideStartDate = exception.overrideStartDate.addingTimeInterval(timedStartDelta)
                    exception.overrideEndDate = exception.overrideEndDate.addingTimeInterval(timedEndDelta)
                }

            case .applyChangedSeriesValues:
                applyChangedSeriesFields(
                    from: oldValues,
                    to: newValues,
                    exception: exception
                )
                if scheduleChanged {
                    let newOriginalStart: Date
                    let newDuration: TimeInterval
                    if newValues.isAllDay {
                        newOriginalStart = AllDayDate.adding(
                            .day,
                            value: startDelta ?? Int(timedStartDelta / 86_400),
                            toStorageDate: oldOriginalStart
                        ) ?? oldOriginalStart
                        newDuration = max(
                            0,
                            AllDayDate.normalizedStorageDate(newValues.endDate)
                                .timeIntervalSince(AllDayDate.normalizedStorageDate(newValues.startDate))
                        )
                    } else {
                        newOriginalStart = oldOriginalStart.addingTimeInterval(timedStartDelta)
                        newDuration = max(0, newValues.endDate.timeIntervalSince(newValues.startDate))
                    }
                    exception.overrideStartDate = newOriginalStart
                    exception.overrideEndDate = newOriginalStart.addingTimeInterval(newDuration)
                }
            }
        }
    }

    private static func applyUnmodifiedSeriesFields(
        from oldValues: RecurringSeriesValues,
        to newValues: RecurringSeriesValues,
        exception: EventOccurrenceException
    ) {
        if exception.overrideTitle == oldValues.title {
            exception.overrideTitle = newValues.title
        }
        if exception.overrideIsAllDay == oldValues.isAllDay {
            exception.overrideIsAllDay = newValues.isAllDay
        }
        if exception.overrideColor == oldValues.color {
            exception.overrideColor = newValues.color
        }
        if exception.overrideMemo == oldValues.memo {
            exception.overrideMemo = newValues.memo
        }

        let alarmWasUnmodified =
            exception.overrideAlarmOption == oldValues.alarmOption &&
            exception.overrideAlarmTimeIntervalBeforeStart == oldValues.alarmTimeIntervalBeforeStart &&
            exception.overrideAlarmCustomValue == oldValues.alarmCustomValue &&
            exception.overrideAlarmCustomUnit == oldValues.alarmCustomUnit
        if alarmWasUnmodified {
            applyAlarm(from: newValues, to: exception)
        }
    }

    private static func applyChangedSeriesFields(
        from oldValues: RecurringSeriesValues,
        to newValues: RecurringSeriesValues,
        exception: EventOccurrenceException
    ) {
        if oldValues.title != newValues.title {
            exception.overrideTitle = newValues.title
        }
        if oldValues.isAllDay != newValues.isAllDay {
            exception.overrideIsAllDay = newValues.isAllDay
        }
        if oldValues.color != newValues.color {
            exception.overrideColor = newValues.color
        }
        if oldValues.memo != newValues.memo {
            exception.overrideMemo = newValues.memo
        }

        let alarmChanged =
            oldValues.alarmOption != newValues.alarmOption ||
            oldValues.alarmTimeIntervalBeforeStart != newValues.alarmTimeIntervalBeforeStart ||
            oldValues.alarmCustomValue != newValues.alarmCustomValue ||
            oldValues.alarmCustomUnit != newValues.alarmCustomUnit
        if alarmChanged {
            applyAlarm(from: newValues, to: exception)
        }
    }

    private static func applyAlarm(
        from values: RecurringSeriesValues,
        to exception: EventOccurrenceException
    ) {
        exception.overrideAlarmOption = values.alarmOption
        exception.overrideAlarmTimeIntervalBeforeStart = values.alarmTimeIntervalBeforeStart
        exception.overrideAlarmCustomValue = values.alarmCustomValue
        exception.overrideAlarmCustomUnit = values.alarmCustomUnit
    }
}
