import Foundation
import SwiftUI

/// 화면 표시 전용 일정 값 타입. 저장하지 않으며 SwiftData `Event`에 종속되지 않는다.
/// 로컬(SwiftData) 일정과 시스템 캘린더(EventKit) 일정을 같은 형태로 합쳐 그리기 위해 사용한다.
struct CalendarDisplayOccurrence: Identifiable, Hashable {
    enum Source: Hashable {
        /// SsCalendar(SwiftData) 일정. 편집 시 이 ID로 원본 `Event`를 찾는다.
        case local(eventID: UUID)
        /// iOS 시스템 캘린더 일정. 이번 단계에서는 읽기 전용이다.
        case system(calendarTitle: String)
    }

    /// 출처 접두어(`local:` / `system:`)를 붙여 서로 충돌하지 않는 ID.
    let id: String
    let source: Source
    let title: String
    let isAllDay: Bool
    let startDate: Date
    let endDate: Date
    let color: Color

    var isSystem: Bool {
        if case .system = source { return true }
        return false
    }

    var localEventID: UUID? {
        if case .local(let eventID) = source { return eventID }
        return nil
    }

    // 아래 두 날짜 계산은 EventOccurrence와 동일한 규칙을 따른다(기존 로컬 일정 배치 보존).

    func occurs(on date: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        guard let nextDayStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: dayStart
        ) else {
            return false
        }

        if isAllDay {
            let eventStartDay = calendar.startOfDay(for: startDate)
            let eventEndDay = calendar.startOfDay(for: endDate)
            return eventStartDay <= dayStart && dayStart <= eventEndDay
        }

        if startDate == endDate {
            return startDate >= dayStart && startDate < nextDayStart
        }

        return startDate < nextDayStart && endDate > dayStart
    }

    func occupiedDayRange(calendar: Calendar) -> ClosedRange<Date> {
        let firstDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        if isAllDay || startDate == endDate || endDate > endDay {
            return firstDay...max(firstDay, endDay)
        }

        let previousDay = calendar.date(
            byAdding: .day,
            value: -1,
            to: endDay
        ) ?? firstDay
        return firstDay...max(firstDay, previousDay)
    }
}

// 앱/위젯 공유 파일(위젯 폴더에 심볼릭 링크). 앱 전용 타입(EventColor 등)에 의존하지 않는다.
// 로컬 일정 변환 init(local:)은 앱 전용 CalendarDisplayOccurrence+Local.swift에 있다.
extension CalendarDisplayOccurrence {
    /// 로컬/시스템 일정을 기존 EventOccurrenceService와 같은 기준(종일 우선, 시작 시각 순)으로 합친다.
    static func merged(
        local: [CalendarDisplayOccurrence],
        system: [CalendarDisplayOccurrence]
    ) -> [CalendarDisplayOccurrence] {
        guard !system.isEmpty else { return local }

        return (local + system).sorted { first, second in
            if first.isAllDay != second.isAllDay {
                return first.isAllDay
            }

            return first.startDate < second.startDate
        }
    }
}
