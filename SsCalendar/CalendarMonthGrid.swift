import Foundation

/// 월간 달력에 필요한 표시 날짜와 주 단위를 계산하는 순수 로직.
struct CalendarMonthGrid {
    static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    static func visibleDates(for date: Date, calendar: Calendar) -> [Date] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: date),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else {
            return []
        }

        var dates: [Date] = []
        var currentDate = firstWeek.start

        while currentDate < lastWeek.end {
            dates.append(currentDate)

            guard let nextDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: currentDate
            ) else {
                break
            }

            currentDate = nextDate
        }

        return dates
    }

    static func visibleWeeks(for date: Date, calendar: Calendar) -> [CalendarWeek] {
        let dates = visibleDates(for: date, calendar: calendar)
        var weeks: [CalendarWeek] = []
        var startIndex = 0

        while startIndex + 7 <= dates.count {
            let weekDates = Array(dates[startIndex..<(startIndex + 7)])
            weeks.append(CalendarWeek(dates: weekDates))
            startIndex += 7
        }

        return weeks
    }
}
