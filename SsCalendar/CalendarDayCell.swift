import SwiftUI
import UIKit

enum CalendarDayContentLayout {
    static let cellHeight: CGFloat = 102
    static let dateHeaderHeight: CGFloat = 38
    static let lunarLineHeight: CGFloat = 12
    static let holidayLineHeight: CGFloat = 14
    static let holidayFontSize: CGFloat = 11.5
    static let holidayHorizontalPadding: CGFloat = 4
    static let contentSpacing: CGFloat = 1

    /// 단일 날짜 일정 제목(CalendarEventBar)에 쓰는 폰트 크기. 2줄 확장 여부를 실제 텍스트 너비로
    /// 판단할 때도 같은 크기를 써야 측정값과 실제 렌더링이 어긋나지 않는다.
    static let singleDayEventFontSize: CGFloat = 11
    /// 단일 날짜 일정 막대 한 칸의 너비 중, 색상 구분선과 여백이 차지해 실제 제목에는 쓸 수 없는 폭.
    /// (칸 간 여백 4pt + 막대 안 HStack의 RoundedRectangle 3pt + spacing 3pt.)
    static let singleDayEventChromeWidth: CGFloat = 10

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
        HolidayDisplayFormatter.title(
            for: holidays.filter(\.isHoliday).map(\.name),
            on: date
        )
    }

    static func holidayLineCount(
        for title: String?,
        availableWidth: CGFloat? = nil
    ) -> Int {
        guard let title else { return 0 }
        let explicitLines = title.split(separator: "\n", omittingEmptySubsequences: false)
        guard let availableWidth else {
            return min(2, explicitLines.count)
        }
        guard availableWidth > 0 else { return 2 }

        let font = UIFont.systemFont(ofSize: holidayFontSize, weight: .medium)
        let renderedLineCount = explicitLines.reduce(into: 0) { count, line in
            let width = (String(line) as NSString).size(withAttributes: [.font: font]).width
            count += max(1, Int(ceil(width / availableWidth)))
        }
        return min(2, renderedLineCount)
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
        holidays: [Holiday],
        availableWidth: CGFloat? = nil
    ) -> CGFloat {
        let title = holidayTitle(for: holidays, on: date)
        return CGFloat(
            holidayLineCount(for: title, availableWidth: availableWidth)
        ) * holidayLineHeight
    }

    static func eventStartY(
        for date: Date,
        holidays: [Holiday],
        calendar: Calendar,
        availableWidth: CGFloat? = nil
    ) -> CGFloat {
        headerEndY(for: date, calendar: calendar)
            + holidayHeight(
                for: date,
                holidays: holidays,
                availableWidth: availableWidth
            )
            + contentSpacing
    }

}

struct CalendarDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let holidays: [Holiday]
    let holidayTopOffset: CGFloat?
    let holidayTextWidth: CGFloat
    /// WeekEventLayout이 일정 밀도까지 반영해 확정한 줄 수. 뷰와 배치 엔진이 같은 높이를 쓴다.
    let displayedHolidayLineCount: Int?
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

    private var holidayLineCount: Int {
        displayedHolidayLineCount ?? CalendarDayContentLayout.holidayLineCount(
            for: holidayTitle,
            availableWidth: holidayTextWidth
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
            .font(.system(size: CalendarDayContentLayout.holidayFontSize, weight: .medium))
            .foregroundStyle(
                Color.red.opacity(isCurrentMonth ? 0.95 : 0.55)
            )
            .multilineTextAlignment(.center)
            .lineLimit(holidayLineCount)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(
                height: CGFloat(holidayLineCount)
                    * CalendarDayContentLayout.holidayLineHeight,
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
        holidayTextWidth: 48,
        displayedHolidayLineCount: nil,
        calendar: Calendar.current
    )
}
