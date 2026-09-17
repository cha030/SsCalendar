import SwiftUI

enum CalendarDayContentLayout {
    static let cellHeight: CGFloat = 102
    static let dateHeaderHeight: CGFloat = 38
    static let lunarLineHeight: CGFloat = 12
    static let holidayLineHeight: CGFloat = 14
    static let contentSpacing: CGFloat = 1

    static func lunarText(for date: Date, calendar: Calendar) -> String? {
        guard calendar.component(.weekday, from: date) == 1 else {
            return nil
        }

        return LunarCalendarService.lunarDate(for: date)?.displayText
    }

    static func holidayTitle(
        for holidays: [Holiday],
        on date: Date
    ) -> String? {
        var names: [String] = []
        let lunarDate = LunarCalendarService.lunarDate(for: date)

        for holiday in holidays where holiday.isHoliday {
            guard shouldDisplayHolidayName(
                holiday.name,
                lunarDate: lunarDate
            ) else {
                continue
            }

            let displayName = displayHolidayName(for: holiday.name)
            guard !displayName.isEmpty, !names.contains(displayName) else {
                continue
            }
            names.append(displayName)
        }

        guard !names.isEmpty else { return nil }
        return names.joined(separator: "\n")
    }

    static func holidayLineCount(for title: String?) -> Int {
        guard let title else { return 0 }
        return min(2, title.split(separator: "\n").count)
    }

    static func headerEndY(
        for date: Date,
        calendar: Calendar
    ) -> CGFloat {
        var offset = dateHeaderHeight

        if lunarText(for: date, calendar: calendar) != nil {
            offset += lunarLineHeight
        }

        return offset
    }

    static func holidayHeight(
        for date: Date,
        holidays: [Holiday]
    ) -> CGFloat {
        let title = holidayTitle(for: holidays, on: date)
        return CGFloat(holidayLineCount(for: title)) * holidayLineHeight
    }

    static func eventStartY(
        for date: Date,
        holidays: [Holiday],
        calendar: Calendar
    ) -> CGFloat {
        headerEndY(for: date, calendar: calendar)
            + holidayHeight(for: date, holidays: holidays)
            + contentSpacing
    }

    private static func shouldDisplayHolidayName(
        _ name: String,
        lunarDate: LunarDate?
    ) -> Bool {
        guard let lunarDate else { return true }

        if name == "설날" {
            return lunarDate.month == 1 && lunarDate.day == 1
        }

        if name == "추석" {
            return lunarDate.month == 8 && lunarDate.day == 15
        }

        return true
    }

    private static func displayHolidayName(for name: String) -> String {
        if name == "1월1일" {
            return "신정"
        }

        if name == "기독탄신일" {
            return "크리스마스"
        }

        if let openingParenthesis = name.firstIndex(of: "(") {
            let prefix = name[..<openingParenthesis]
            let suffix = name[openingParenthesis...]
            return "\(prefix)\n\(suffix)"
        }

        guard name.count > 5 else {
            return name
        }

        let middleOffset = Int(ceil(Double(name.count) / 2))
        let middleIndex = name.index(name.startIndex, offsetBy: middleOffset)
        return "\(name[..<middleIndex])\n\(name[middleIndex...])"
    }
}

struct CalendarDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let holidays: [Holiday]
    let holidayTopOffset: CGFloat?
    let calendar: Calendar

    private var lunarDateText: String? {
        CalendarDayContentLayout.lunarText(for: date, calendar: calendar)
    }

    private var holidayTitle: String? {
        CalendarDayContentLayout.holidayTitle(
            for: holidays,
            on: date
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                dateHeader

                if let lunarDateText {
                    Text(lunarDateText)
                        .font(.system(size: 10))
                        .foregroundStyle(
                            Color.secondary.opacity(
                                isCurrentMonth ? 0.85 : 0.4
                            )
                        )
                        .frame(
                            height: CalendarDayContentLayout.lunarLineHeight
                        )
                }

                if holidayTopOffset == nil, let holidayTitle {
                    holidayLabel(holidayTitle)
                }

                Spacer(minLength: 0)
            }

            if let holidayTopOffset, let holidayTitle {
                holidayLabel(holidayTitle)
                    .offset(y: holidayTopOffset)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: CalendarDayContentLayout.cellHeight,
            maxHeight: CalendarDayContentLayout.cellHeight,
            alignment: .top
        )
        .overlay(alignment: .top) {
            if isSelected {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .padding(.horizontal, 2)
                    .frame(height: CalendarDayContentLayout.cellHeight - 6)
                    .padding(.top, 2)
            }
        }
    }

    private func holidayLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(
                Color.red.opacity(isCurrentMonth ? 0.95 : 0.55)
            )
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(
                maxWidth: .infinity,
                minHeight: CGFloat(
                    CalendarDayContentLayout.holidayLineCount(for: title)
                ) * CalendarDayContentLayout.holidayLineHeight,
                alignment: .top
            )
            .padding(.horizontal, 2)
    }

    private var dateHeader: some View {
        ZStack(alignment: .top) {
            if isToday {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .padding(.top, 3)
            }

            Text("\(calendar.component(.day, from: date))")
                .font(.body)
                .foregroundStyle(isToday ? Color.white : dateColor)
                .padding(.top, 8)
        }
        .frame(height: CalendarDayContentLayout.dateHeaderHeight)
    }

    private var isHoliday: Bool {
        holidays.contains { $0.isHoliday }
    }

    private var dateColor: Color {
        if isHoliday {
            return .red.opacity(isCurrentMonth ? 1 : 0.55)
        }

        if !isCurrentMonth {
            return .secondary.opacity(0.45)
        }

        let weekday = calendar.component(.weekday, from: date)

        if weekday == 1 {
            return .red
        } else if weekday == 7 {
            return .blue
        } else {
            return .primary
        }
    }
}

#Preview {
    CalendarDayCell(
        date: Date(),
        isCurrentMonth: true,
        isToday: true,
        isSelected: true,
        holidays: [
            Holiday(
                date: Date(),
                name: "대체공휴일(개천절)",
                isHoliday: true
            )
        ],
        holidayTopOffset: 58,
        calendar: Calendar.current
    )
}
