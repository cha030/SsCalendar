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
        guard LunarDisplaySetting.isEnabled else { return nil }
        guard calendar.component(.weekday, from: date) == 1 else {
            return nil
        }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return LunarCalendarService.lunarDate(year: year, month: month, day: day)?.displayText
    }

    static func holidayTitle(
        for holidays: [Holiday],
        on date: Date,
        calendar: Calendar = DeviceCalendar.current
    ) -> String? {
        HolidayDisplayFormatter.title(
            for: holidays.filter(\.isHoliday).map(\.name),
            on: date,
            calendar: calendar
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
        availableWidth: CGFloat? = nil,
        calendar: Calendar = DeviceCalendar.current
    ) -> CGFloat {
        let title = holidayTitle(for: holidays, on: date, calendar: calendar)
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
                availableWidth: availableWidth,
                calendar: calendar
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
    let importantMarker: ImportantMarker

    @AppStorage(LunarDisplaySetting.storageKey, store: LunarDisplaySetting.store)
    private var showLunarDates = false
    @AppStorage(HolidayCountry.storageKey, store: HolidayCountry.settingsStore)
    private var holidayCountryRawValue = HolidayCountry.defaultCountry.rawValue

    private var usesColoredWeekends: Bool {
        (HolidayCountry(rawValue: holidayCountryRawValue) ?? HolidayCountry.defaultCountry).usesColoredWeekendsForDisplay
    }

    private var lunarDateText: String? {
        guard showLunarDates else { return nil }
        return CalendarDayContentLayout.lunarText(for: date, calendar: calendar)
    }

    private var holidayTitle: String? {
        CalendarDayContentLayout.holidayTitle(
            for: holidays,
            on: date,
            calendar: calendar
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
                // "+n" 오버플로 줄의 최대 y(= rowHeight, WeekEventLayout이 보장)까지 테두리 안에
                // 들어오도록 세로 길이를 늘렸다(기존 cellHeight-6에서 5pt 추가, 폰트 렌더링 여유 1pt 포함).
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .padding(.horizontal, 2)
                    .frame(height: CalendarDayContentLayout.cellHeight - 1)
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

            ImportantMarkerStamp(marker: importantMarker)
                .allowsHitTesting(false)

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

        if usesColoredWeekends, weekday == 1 {
            return .red
        } else if usesColoredWeekends, weekday == 7 {
            return .blue
        } else {
            return .primary
        }
    }
}

enum ImportantMarkerStyle {
    static var gold: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 235 / 255, green: 180 / 255, blue: 50 / 255, alpha: 1)
            }
            return UIColor(red: 214 / 255, green: 158 / 255, blue: 20 / 255, alpha: 1)
        })
    }
}

private struct ImportantMarkerStamp: View {
    let marker: ImportantMarker

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 34

    private var lineWidth: CGFloat {
        max(1.5, diameter * 0.065)
    }

    var body: some View {
        Group {
            switch marker {
            case .none:
                EmptyView()
            case .star:
                ImportantMarkerStarShape()
                    .stroke(ImportantMarkerStyle.gold, lineWidth: lineWidth)
            case .sun:
                ImportantMarkerSunShape()
                    .stroke(ImportantMarkerStyle.gold, lineWidth: lineWidth)
            }
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(10))
        .allowsHitTesting(false)
    }
}

private struct ImportantMarkerStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.42
        var path = Path()

        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = (-Double.pi / 2) + (Double(index) * Double.pi / 5)
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct ImportantMarkerSunShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let ringRadius = radius * 0.48
        let rayStart = radius * 0.63
        let rayEnd = radius * 0.9
        var path = Path()
        path.addEllipse(in: CGRect(
            x: center.x - ringRadius,
            y: center.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))

        for index in 0..<11 {
            let angle = -Double.pi / 2 + (Double(index) * 2 * Double.pi / 11)
            path.move(to: CGPoint(
                x: center.x + CGFloat(cos(angle)) * rayStart,
                y: center.y + CGFloat(sin(angle)) * rayStart
            ))
            path.addLine(to: CGPoint(
                x: center.x + CGFloat(cos(angle)) * rayEnd,
                y: center.y + CGFloat(sin(angle)) * rayEnd
            ))
        }
        return path
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
        calendar: Calendar.current,
        importantMarker: .none
    )
}

#Preview("표시 조합") {
    HStack(spacing: 8) {
        CalendarDayCell(
            date: Date(),
            isCurrentMonth: true,
            isToday: false,
            isSelected: false,
            holidays: [],
            holidayTopOffset: nil,
            holidayTextWidth: 48,
            displayedHolidayLineCount: nil,
            calendar: Calendar.current,
            importantMarker: .star
        )
        CalendarDayCell(
            date: Date(),
            isCurrentMonth: true,
            isToday: false,
            isSelected: false,
            holidays: [],
            holidayTopOffset: nil,
            holidayTextWidth: 48,
            displayedHolidayLineCount: nil,
            calendar: Calendar.current,
            importantMarker: .sun
        )
    }
    .frame(width: 160)
}

#Preview("오늘·다크·큰 글자") {
    CalendarDayCell(
        date: Date(),
        isCurrentMonth: true,
        isToday: true,
        isSelected: false,
        holidays: [],
        holidayTopOffset: nil,
        holidayTextWidth: 48,
        displayedHolidayLineCount: nil,
        calendar: Calendar.current,
        importantMarker: .sun
    )
    .environment(\.colorScheme, .dark)
    .dynamicTypeSize(.accessibility5)
    .frame(width: 80)
}

#Preview("일정 제목과 표시") {
    let calendar = Calendar.current
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    let dates = (0..<7).compactMap {
        calendar.date(byAdding: .day, value: $0, to: weekStart)
    }
    let eventDate = dates[2]
    CalendarWeekRow(
        week: CalendarWeek(dates: dates),
        occurrences: [
            CalendarDisplayOccurrence(
                id: "preview-marker-event",
                source: .local(eventID: UUID()),
                title: "중요한 일정",
                isAllDay: false,
                startDate: eventDate,
                endDate: eventDate.addingTimeInterval(3600),
                color: .blue,
                importantMarker: .star,
                createdAt: Date()
            )
        ],
        holidaysByDate: [:],
        currentDate: eventDate,
        selectedDate: eventDate,
        calendar: calendar,
        onSelectDate: { _ in }
    )
    .frame(height: CalendarDayContentLayout.cellHeight)
}
