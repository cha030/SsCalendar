import Foundation

struct LunarDate: Equatable, Sendable {
    let month: Int
    let day: Int
    let isLeapMonth: Bool

    var displayText: String {
        let prefix = isLeapMonth ? "윤" : ""
        return "\(prefix)\(month).\(day)"
    }
}

enum LunarCalendarService {
    private static let seoulTimeZone =
        TimeZone(identifier: "Asia/Seoul") ?? .current

    static func lunarDate(year: Int, month: Int, day: Int) -> LunarDate? {
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = seoulTimeZone
        guard let normalizedDate = gregorianCalendar.date(
            from: DateComponents(
                timeZone: seoulTimeZone,
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        ) else {
            return nil
        }

        var lunarCalendar = Calendar(identifier: .dangi)
        lunarCalendar.timeZone = seoulTimeZone

        let lunarComponents = lunarCalendar.dateComponents(
            [.month, .day],
            from: normalizedDate
        )

        guard
            let lunarMonth = lunarComponents.month,
            let lunarDay = lunarComponents.day
        else {
            return nil
        }

        return LunarDate(
            month: lunarMonth,
            day: lunarDay,
            isLeapMonth: lunarComponents.isLeapMonth ?? false
        )
    }
}
