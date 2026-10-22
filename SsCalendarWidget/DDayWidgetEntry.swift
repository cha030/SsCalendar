import Foundation
import WidgetKit

/// 잠금화면 D-Day 위젯이 보여줄 한 일정의 요약. `CalendarDisplayOccurrence`(Color 포함)를 그대로
/// 쓰지 않고 필요한 값만 뽑아 Sendable 요구 조건을 쉽게 만족시킨다(TodayWidgetOccurrenceSummary와 같은 방식).
struct DDayWidgetItemSummary: Hashable, Sendable {
    /// 화면에 실제로 보여줄 제목. "잠금화면 일정 제목 표시"가 꺼져 있으면 대체 문구("일정 있음")다.
    let displayTitle: String
    /// true면 displayTitle이 실제 일정 제목이라는 뜻이다. 대체 문구일 때는 더 가릴 필요가 없다.
    let isSensitiveTitle: Bool
    let startDate: Date
    let dateString: String
    let daysRemaining: Int
}

/// 잠금화면 D-Day·D-Day Next 위젯이 공유하는 엔트리. 한 번에 일정 하나만 보여준다.
struct DDayWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let dateString: String
    let item: DDayWidgetItemSummary?
}

extension DDayWidgetEntry {
    /// D-Day 위젯 갤러리 미리보기용 샘플 상태.
    static var placeholder: DDayWidgetEntry {
        let now = Date()
        return DDayWidgetEntry(
            date: now,
            dateString: CalendarWidgetCalendar.dateString(for: now),
            item: DDayWidgetItemSummary(
                displayTitle: String(localized: "생일 파티"),
                isSensitiveTitle: false,
                startDate: now.addingTimeInterval(86_400 * 3),
                dateString: CalendarWidgetCalendar.dateString(for: now.addingTimeInterval(86_400 * 3)),
                daysRemaining: 3
            )
        )
    }

    /// D-Day Next 위젯 갤러리 미리보기용 샘플 상태.
    static var nextPlaceholder: DDayWidgetEntry {
        let now = Date()
        return DDayWidgetEntry(
            date: now,
            dateString: CalendarWidgetCalendar.dateString(for: now),
            item: DDayWidgetItemSummary(
                displayTitle: String(localized: "여행"),
                isSensitiveTitle: false,
                startDate: now.addingTimeInterval(86_400 * 10),
                dateString: CalendarWidgetCalendar.dateString(for: now.addingTimeInterval(86_400 * 10)),
                daysRemaining: 10
            )
        )
    }

    static func empty(for date: Date) -> DDayWidgetEntry {
        DDayWidgetEntry(date: date, dateString: CalendarWidgetCalendar.dateString(for: date), item: nil)
    }
}
