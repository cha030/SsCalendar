import Foundation
import WidgetKit

/// 홈 화면 D-Day 위젯에 보여줄 한 일정.
struct DDayHomeWidgetItem: Hashable, Sendable {
    let displayTitle: String
    let isSensitiveTitle: Bool
    let startDate: Date
    let dateString: String
    let originalStartDate: Date
    let originalDateString: String
    let localEventID: UUID?
    let daysRemaining: Int
}

/// 홈 화면 D-Day 위젯(Small/Medium)의 엔트리. 가장 가까운 순으로 최대 2건까지 담는다
/// (Small은 뷰에서 첫 번째만 쓰고, Medium은 둘 다 쓴다).
struct DDayHomeWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let items: [DDayHomeWidgetItem]
}

extension DDayHomeWidgetEntry {
    static var placeholder: DDayHomeWidgetEntry {
        let now = Date()
        return DDayHomeWidgetEntry(
            date: now,
            items: [
                DDayHomeWidgetItem(
                    displayTitle: String(localized: "생일 파티"),
                    isSensitiveTitle: false,
                    startDate: now.addingTimeInterval(86_400 * 3),
                    dateString: CalendarWidgetCalendar.dateString(for: now.addingTimeInterval(86_400 * 3)),
                    originalStartDate: now.addingTimeInterval(86_400 * 3),
                    originalDateString: CalendarWidgetCalendar.dateString(for: now.addingTimeInterval(86_400 * 3)),
                    localEventID: nil,
                    daysRemaining: 3
                ),
                DDayHomeWidgetItem(
                    displayTitle: String(localized: "여행"),
                    isSensitiveTitle: false,
                    startDate: now.addingTimeInterval(86_400 * 10),
                    dateString: CalendarWidgetCalendar.dateString(for: now.addingTimeInterval(86_400 * 10)),
                    originalStartDate: now.addingTimeInterval(86_400 * 10),
                    originalDateString: CalendarWidgetCalendar.dateString(for: now.addingTimeInterval(86_400 * 10)),
                    localEventID: nil,
                    daysRemaining: 10
                )
            ]
        )
    }

    static func empty(for date: Date) -> DDayHomeWidgetEntry {
        DDayHomeWidgetEntry(date: date, items: [])
    }
}
