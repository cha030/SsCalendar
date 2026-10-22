import Foundation
import WidgetKit

/// 잠금화면에 보여줄 한 일정의 요약. `CalendarDisplayOccurrence`(Color 포함)를 그대로 쓰지 않고
/// 필요한 값만 뽑아 Sendable 요구 조건을 쉽게 만족시킨다(CalendarWidgetEvent/Occurrence와 같은 방식).
struct TodayWidgetOccurrenceSummary: Hashable, Sendable {
    /// 화면에 실제로 보여줄 제목. "잠금화면 일정 제목 표시"가 꺼져 있으면 이미 대체 문구("일정 있음")로 바뀐 값이다.
    let displayTitle: String
    /// true면 displayTitle이 실제 일정 제목이라는 뜻이다. 대체 문구일 때는 더 가릴 필요가 없다.
    let isSensitiveTitle: Bool
    let isAllDay: Bool
    /// true면 지금 진행 중인 일정이라는 뜻이다("진행" 표시). Next 위젯의 일정은 항상 false다.
    let isOngoing: Bool
    let startDate: Date
    let endDate: Date
}

/// 잠금화면 Today·Next 위젯이 공유하는 엔트리. 한 번에 일정 하나만 보여준다.
/// `occurrence`가 nil이면 해당 위젯의 "일정 없음" 문구를 보여준다(Today/Next는 문구만 다르다 — TodayWidgetView/NextWidgetView 참고).
struct TodayWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let dateString: String
    let occurrence: TodayWidgetOccurrenceSummary?
}

extension TodayWidgetEntry {
    /// Today 위젯 갤러리 미리보기 등 실제 데이터 없이 보여줄 샘플 상태(진행 중인 일정).
    static var placeholder: TodayWidgetEntry {
        let now = Date()
        return TodayWidgetEntry(
            date: now,
            dateString: CalendarWidgetCalendar.dateString(for: now),
            occurrence: TodayWidgetOccurrenceSummary(
                displayTitle: String(localized: "디자인 리뷰"),
                isSensitiveTitle: false,
                isAllDay: false,
                isOngoing: true,
                startDate: now,
                endDate: now.addingTimeInterval(3_600)
            )
        )
    }

    /// Next 위젯 갤러리 미리보기용 샘플 상태(예정된 일정, 진행 중 아님).
    static var nextPlaceholder: TodayWidgetEntry {
        let now = Date()
        return TodayWidgetEntry(
            date: now,
            dateString: CalendarWidgetCalendar.dateString(for: now),
            occurrence: TodayWidgetOccurrenceSummary(
                displayTitle: String(localized: "회의"),
                isSensitiveTitle: false,
                isAllDay: false,
                isOngoing: false,
                startDate: now.addingTimeInterval(9_000),
                endDate: now.addingTimeInterval(12_600)
            )
        )
    }

    static func empty(for date: Date) -> TodayWidgetEntry {
        TodayWidgetEntry(date: date, dateString: CalendarWidgetCalendar.dateString(for: date), occurrence: nil)
    }
}
