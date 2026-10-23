import SwiftUI

// 앱 전용: 앱 타깃의 EventColor(EventEditorView.swift)에 의존하므로 위젯과 공유하지 않는다.
extension CalendarDisplayOccurrence {
    /// 기존 반복 엔진(EventOccurrenceService)이 만든 로컬 발생 일정을 표시 모델로 변환한다.
    init(local occurrence: EventOccurrence) {
        let startDate = occurrence.isAllDay
            ? AllDayDate.displayDate(fromStorageDate: occurrence.startDate)
            : occurrence.startDate
        let endDate = occurrence.isAllDay
            ? AllDayDate.displayDate(fromStorageDate: occurrence.endDate)
            : occurrence.endDate
        self.init(
            id: "local:\(occurrence.event.id.uuidString):\(occurrence.startDate.timeIntervalSince1970)",
            source: .local(eventID: occurrence.event.id),
            title: occurrence.title,
            isAllDay: occurrence.isAllDay,
            startDate: startDate,
            endDate: endDate,
            color: EventColor(rawValue: occurrence.colorName)?.color ?? .gray,
            originalStartDate: occurrence.originalStartDate,
            importantMarker: occurrence.event.importantMarker,
            createdAt: occurrence.event.createdAt
        )
    }
}
