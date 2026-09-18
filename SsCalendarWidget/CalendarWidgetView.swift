import AppIntents
import SwiftUI
import WidgetKit

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarWidgetEntry

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(spacing: sectionSpacing) {
            header
            weekdayHeader

            GeometryReader { geometry in
                let weeks = calendarWeeks
                let weekCount = max(1, weeks.count)
                let rowSpacing = calendarRowSpacing
                let rowHeight =
                    (geometry.size.height - CGFloat(weekCount - 1) * rowSpacing)
                    / CGFloat(weekCount)

                if family == .systemMedium {
                    mediumGrid(rowHeight: rowHeight)
                } else {
                    VStack(spacing: rowSpacing) {
                        ForEach(weeks) { week in
                            CalendarWidgetWeekView(
                                week: week,
                                occurrences: entry.occurrences,
                                selectedDate: entry.selectedDate,
                                family: family,
                                weekCount: weekCount
                            )
                            .frame(height: rowHeight)
                            .transition(.identity)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .invalidatableContent()
                }
            }
            .id(entry.monthStart)
            .transition(.identity)
        }
        .padding(contentPadding)
        .contentTransition(.identity)
        .widgetURL(CalendarWidgetDeepLink.monthURL(for: entry.monthStart))
        .containerBackground(Color(uiColor: .systemBackground), for: .widget)
    }

    private var header: some View {
        ZStack {
            HStack(spacing: navigationSpacing) {
                Button(intent: PreviousWidgetMonthIntent()) {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("이전 달")

                Text(monthTitle)
                    .font(monthTitleFont)
                    .lineLimit(1)
                    .frame(minWidth: monthTitleWidth)
                    .contentTransition(.identity)

                Button(intent: NextWidgetMonthIntent()) {
                    Image(systemName: "chevron.right")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("다음 달")
            }

            HStack(spacing: 5) {
                Spacer()

                Link(destination: CalendarWidgetDeepLink.newEventURL(for: selectedDateForNewEvent)) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: todayButtonSize, height: todayButtonSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("선택한 날짜에 일정 추가")

                Button(intent: CurrentWidgetMonthIntent()) {
                    Text(todayDayNumber)
                        .font(todayButtonFont)
                        .frame(width: todayButtonSize, height: todayButtonSize)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.primary, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("현재 달로 돌아가기")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .foregroundStyle(.primary)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.system(size: weekdayFontSize, weight: .medium))
                    .foregroundStyle(weekdayColor(at: index))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func mediumGrid(rowHeight: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: calendarRowSpacing) {
            ForEach(entry.days) { day in
                CalendarWidgetMediumDayView(
                    day: day,
                    isSelected: isSelected(day.date)
                )
                    .frame(height: rowHeight, alignment: .top)
                    .transition(.identity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .invalidatableContent()
    }

    private var calendarWeeks: [CalendarWidgetWeek] {
        stride(from: 0, to: entry.days.count, by: 7).compactMap { start in
            let end = min(start + 7, entry.days.count)
            guard end - start == 7 else { return nil }
            return CalendarWidgetWeek(days: Array(entry.days[start..<end]))
        }
    }

    private var monthTitle: String {
        let calendar = CalendarWidgetCalendar.korean
        let displayed = calendar.dateComponents([.year, .month], from: entry.monthStart)
        let current = calendar.dateComponents([.year], from: Date())
        let month = displayed.month ?? 1

        if displayed.year == current.year {
            return "\(month)월"
        }
        return "\(displayed.year ?? 1)년 \(month)월"
    }

    private func weekdayColor(at index: Int) -> Color {
        if index == 0 { return .red }
        if index == 6 { return .blue }
        return .secondary
    }

    private var isExtraLargePortrait: Bool {
        family == .systemExtraLargePortrait
    }

    private var sectionSpacing: CGFloat {
        if isExtraLargePortrait { return 13 }
        return family == .systemLarge ? 9 : 4
    }

    private var calendarRowSpacing: CGFloat {
        if isExtraLargePortrait { return 10 }
        return family == .systemLarge ? 6 : 1
    }

    private var contentPadding: CGFloat {
        if isExtraLargePortrait { return 14 }
        return family == .systemLarge ? 11 : 10
    }

    private var monthTitleFont: Font {
        if isExtraLargePortrait { return .title3.weight(.semibold) }
        return family == .systemLarge ? .headline : .subheadline.weight(.semibold)
    }

    private var weekdayFontSize: CGFloat {
        if isExtraLargePortrait { return 12 }
        return family == .systemLarge ? 11 : 9
    }

    private var todayButtonFont: Font {
        .system(size: isExtraLargePortrait ? 11 : 9, weight: .semibold)
    }

    private var todayButtonSize: CGFloat {
        isExtraLargePortrait ? 26 : 24
    }

    private var todayDayNumber: String {
        String(CalendarWidgetCalendar.korean.component(.day, from: Date()))
    }

    private var selectedDateForNewEvent: Date {
        entry.selectedDate ?? Date()
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate = entry.selectedDate else { return false }
        return CalendarWidgetCalendar.korean.isDate(date, inSameDayAs: selectedDate)
    }

    private var monthTitleWidth: CGFloat {
        if isExtraLargePortrait { return 92 }
        return family == .systemLarge ? 84 : 76
    }

    private var navigationSpacing: CGFloat {
        isExtraLargePortrait ? 8 : 4
    }

    private var headerGroupSpacing: CGFloat {
        isExtraLargePortrait ? 12 : 8
    }
}

private struct CalendarWidgetWeek: Identifiable {
    let days: [CalendarWidgetDay]

    var id: Date {
        days.first?.date ?? .distantPast
    }
}

private struct CalendarWidgetWeekView: View {
    let week: CalendarWidgetWeek
    let occurrences: [CalendarWidgetOccurrence]
    let selectedDate: Date?
    let family: WidgetFamily
    let weekCount: Int

    var body: some View {
        GeometryReader { geometry in
            let metrics = CalendarWidgetWeekMetrics(
                family: family,
                weekCount: weekCount,
                rowHeight: geometry.size.height
            )
            let layout = CalendarWidgetWeekLayout(
                week: week,
                occurrences: occurrences,
                maximumSlots: metrics.maximumMultiDaySlots
            )
            let columnWidth = geometry.size.width / 7

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(week.days.enumerated()), id: \.element.id) { column, day in
                        CalendarWidgetExpandedDayView(
                            day: day,
                            isSelected: isSelected(day.date),
                            singleDayEvents: singleDayEvents(for: day),
                            hiddenMultiDayCount: layout.hiddenCounts[column, default: 0],
                            multiDaySlotCount: layout.occupiedSlotCounts[column, default: 0],
                            metrics: metrics
                        )
                        .frame(width: columnWidth, height: geometry.size.height)
                    }
                }

                ForEach(layout.visibleSegments) { segment in
                    CalendarWidgetMultiDayBar(segment: segment, metrics: metrics)
                        .frame(
                            width: columnWidth * CGFloat(segment.endColumn - segment.startColumn + 1) - 2,
                            height: metrics.multiDayBarHeight
                        )
                        .offset(
                            x: columnWidth * CGFloat(segment.startColumn) + 1,
                            y: metrics.multiDayStartY
                                + CGFloat(segment.slot)
                                * (metrics.multiDayBarHeight + metrics.multiDaySpacing)
                        )
                }
            }
        }
    }

    private func singleDayEvents(for day: CalendarWidgetDay) -> [CalendarWidgetEvent] {
        let singleDayIDs = Set(
            occurrences.lazy.filter { !$0.isMultiDay }.map(\.id)
        )
        return day.events.filter { singleDayIDs.contains($0.id) }
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return CalendarWidgetCalendar.korean.isDate(date, inSameDayAs: selectedDate)
    }
}

private struct CalendarWidgetExpandedDayView: View {
    let day: CalendarWidgetDay
    let isSelected: Bool
    let singleDayEvents: [CalendarWidgetEvent]
    let hiddenMultiDayCount: Int
    let multiDaySlotCount: Int
    let metrics: CalendarWidgetWeekMetrics

    private var calendar: Calendar { CalendarWidgetCalendar.korean }

    var body: some View {
        GeometryReader { geometry in
            let contentStart = metrics.multiDayStartY
                + CGFloat(multiDaySlotCount)
                * (metrics.multiDayBarHeight + metrics.multiDaySpacing)
            let lunarHeight = lunarText == nil ? 0 : metrics.lunarLineHeight
            let holidayHeight = day.holidayTitle == nil ? 0 : metrics.holidayLineHeight
            let availableHeight = max(
                0,
                geometry.size.height - contentStart - lunarHeight - holidayHeight
            )
            let eventCapacity = max(
                0,
                Int(availableHeight / metrics.eventLineHeight)
            )
            let initiallyHiddenCount =
                hiddenMultiDayCount
                + max(0, singleDayEvents.count - eventCapacity)
            let visibleEventCount = min(
                singleDayEvents.count,
                initiallyHiddenCount > 0 ? max(0, eventCapacity - 1) : eventCapacity
            )
            let hiddenCount =
                hiddenMultiDayCount + singleDayEvents.count - visibleEventCount

            ZStack(alignment: .top) {
                dateControls

                VStack(alignment: .leading, spacing: 1) {
                    if let lunarText {
                        Text(lunarText)
                            .font(.system(size: metrics.lunarFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: metrics.lunarLineHeight
                            )
                    }

                    if let holidayTitle = day.holidayTitle {
                        Text(holidayTitle.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: metrics.holidayFontSize, weight: .medium))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: metrics.holidayLineHeight
                            )
                    }

                    ForEach(Array(singleDayEvents.prefix(visibleEventCount))) { event in
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(CalendarWidgetColor.color(for: event.colorName))
                                .frame(width: 2, height: metrics.eventIndicatorHeight)

                            Text(event.title)
                                .font(.system(size: metrics.eventFontSize))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(height: metrics.eventLineHeight)
                    }

                    if hiddenCount > 0 {
                        Text("+\(hiddenCount)")
                            .font(.system(size: metrics.overflowFontSize, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 2)
                .offset(y: contentStart)
            }
        }
        .opacity(day.isCurrentMonth ? 1 : 0.45)
        .background {
            Button(intent: SelectWidgetDateIntent(date: day.date)) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
                    .padding(1)
            }
        }
    }

    private var dateNumber: some View {
        Text(day.date, format: .dateTime.day())
            .font(
                .system(
                    size: metrics.dateFontSize,
                    weight: day.isToday ? .semibold : .regular
                )
            )
            .foregroundStyle(day.isToday ? Color.white : dateColor)
            .frame(width: metrics.dateBadgeSize, height: metrics.dateBadgeSize)
            .background {
                if day.isToday {
                    Circle().fill(Color.blue)
                }
            }
            .frame(maxWidth: .infinity)
    }

    private var dateControls: some View {
        ZStack {
            Link(destination: CalendarWidgetDeepLink.dayURL(for: day.date)) {
                dateNumber
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var lunarText: String? {
        guard calendar.component(.weekday, from: day.date) == 1 else {
            return nil
        }
        return LunarCalendarService.lunarDate(for: day.date)?.displayText
    }

    private var dateColor: Color {
        if day.isHoliday { return .red }

        switch calendar.component(.weekday, from: day.date) {
        case 1: return .red
        case 7: return .blue
        default: return .primary
        }
    }
}

private struct CalendarWidgetMediumDayView: View {
    let day: CalendarWidgetDay
    let isSelected: Bool

    private var calendar: Calendar { CalendarWidgetCalendar.korean }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Link(destination: CalendarWidgetDeepLink.dayURL(for: day.date)) {
                    Text(day.date, format: .dateTime.day())
                        .font(
                            .system(
                                size: 10,
                                weight: day.isToday ? .semibold : .regular
                            )
                        )
                        .foregroundStyle(day.isToday ? Color.white : dateColor)
                        .frame(width: 17, height: 17)
                        .background {
                            if day.isToday {
                                Circle().fill(Color.blue)
                            }
                        }
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 2) {
                ForEach(Array(day.events.prefix(3))) { event in
                    Circle()
                        .fill(CalendarWidgetColor.color(for: event.colorName))
                        .frame(width: 3.5, height: 3.5)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(day.isCurrentMonth ? 1 : 0.45)
        .background {
            Button(intent: SelectWidgetDateIntent(date: day.date)) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
                    .padding(1)
            }
        }
    }

    private var dateColor: Color {
        if day.isHoliday { return .red }

        switch calendar.component(.weekday, from: day.date) {
        case 1: return .red
        case 7: return .blue
        default: return .primary
        }
    }
}

private struct CalendarWidgetMultiDayBar: View {
    let segment: CalendarWidgetWeekSegment
    let metrics: CalendarWidgetWeekMetrics

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(CalendarWidgetColor.color(for: segment.occurrence.colorName))

            if segment.showsTitle {
                Text(segment.occurrence.title)
                    .font(.system(size: metrics.multiDayFontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 3)
            }
        }
    }
}

private struct CalendarWidgetWeekSegment: Identifiable {
    let occurrence: CalendarWidgetOccurrence
    let startColumn: Int
    let endColumn: Int
    let slot: Int
    let showsTitle: Bool

    var id: String {
        "\(occurrence.id)-\(startColumn)-\(endColumn)"
    }
}

private struct CalendarWidgetWeekLayout {
    let visibleSegments: [CalendarWidgetWeekSegment]
    let hiddenCounts: [Int: Int]
    let visibleSlotCount: Int
    let occupiedSlotCounts: [Int: Int]

    init(
        week: CalendarWidgetWeek,
        occurrences: [CalendarWidgetOccurrence],
        maximumSlots: Int
    ) {
        guard let weekStart = week.days.first?.date,
              let weekEnd = week.days.last?.date else {
            visibleSegments = []
            hiddenCounts = [:]
            visibleSlotCount = 0
            occupiedSlotCounts = [:]
            return
        }

        let calendar = CalendarWidgetCalendar.korean
        let candidates = occurrences
            .filter {
                $0.isMultiDay
                    && $0.lastDay >= weekStart
                    && $0.firstDay <= weekEnd
            }
            .map { occurrence in
                (
                    occurrence: occurrence,
                    segmentStart: max(occurrence.firstDay, weekStart),
                    segmentEnd: min(occurrence.lastDay, weekEnd)
                )
            }
            .sorted {
                if $0.segmentStart != $1.segmentStart {
                    return $0.segmentStart < $1.segmentStart
                }
                if $0.segmentEnd != $1.segmentEnd {
                    return $0.segmentEnd > $1.segmentEnd
                }
                return $0.occurrence.id < $1.occurrence.id
            }

        var segments: [CalendarWidgetWeekSegment] = []
        var hidden: [Int: Int] = [:]
        var slotEndColumns: [Int] = []

        for candidate in candidates {
            let occurrence = candidate.occurrence
            let startColumn = calendar.dateComponents(
                [.day],
                from: weekStart,
                to: candidate.segmentStart
            ).day ?? 0
            let endColumn = calendar.dateComponents(
                [.day],
                from: weekStart,
                to: candidate.segmentEnd
            ).day ?? startColumn
            let slot = slotEndColumns.firstIndex(where: { $0 < startColumn })
                ?? slotEndColumns.count

            guard slot < maximumSlots else {
                for column in startColumn...endColumn {
                    hidden[column, default: 0] += 1
                }
                continue
            }

            if slot == slotEndColumns.count {
                slotEndColumns.append(endColumn)
            } else {
                slotEndColumns[slot] = endColumn
            }

            segments.append(
                CalendarWidgetWeekSegment(
                    occurrence: occurrence,
                    startColumn: startColumn,
                    endColumn: endColumn,
                    slot: slot,
                    showsTitle: true
                )
            )
        }

        visibleSegments = segments
        hiddenCounts = hidden
        visibleSlotCount = min(
            maximumSlots,
            (segments.map(\.slot).max() ?? -1) + 1
        )
        occupiedSlotCounts = Dictionary(
            uniqueKeysWithValues: (0..<7).map { column in
                let occupiedCount = segments
                    .filter { $0.startColumn <= column && column <= $0.endColumn }
                    .map(\.slot)
                    .max()
                    .map { $0 + 1 } ?? 0
                return (column, occupiedCount)
            }
        )
    }

}

private struct CalendarWidgetWeekMetrics {
    let family: WidgetFamily
    let weekCount: Int
    let rowHeight: CGFloat

    var isExtraLarge: Bool {
        family == .systemExtraLargePortrait
    }

    var isCompactSixWeekLarge: Bool {
        family == .systemLarge && weekCount >= 6
    }

    var dateFontSize: CGFloat {
        if isExtraLarge { return 14 }
        return isCompactSixWeekLarge ? 11 : 12
    }

    var dateBadgeSize: CGFloat {
        if isExtraLarge { return 24 }
        return isCompactSixWeekLarge ? 17 : 20
    }

    var lunarFontSize: CGFloat {
        if isExtraLarge { return 9 }
        return isCompactSixWeekLarge ? 6.5 : 7.5
    }

    var lunarLineHeight: CGFloat {
        if isExtraLarge { return 12 }
        return isCompactSixWeekLarge ? 7 : 9
    }

    var multiDayStartY: CGFloat {
        dateBadgeSize + 1
    }

    var multiDayBarHeight: CGFloat {
        if isExtraLarge { return 14 }
        return isCompactSixWeekLarge ? 8 : 10
    }

    var multiDaySpacing: CGFloat {
        isExtraLarge ? 2 : 1
    }

    var maximumMultiDaySlots: Int {
        let preferred: Int
        if isExtraLarge {
            preferred = weekCount >= 6 ? 3 : 4
        } else {
            preferred = weekCount >= 6 ? 1 : 2
        }

        let available = max(0, rowHeight - multiDayStartY - minimumLowerContentHeight)
        let slotHeight = multiDayBarHeight + multiDaySpacing
        return max(1, min(preferred, Int(available / slotHeight)))
    }

    var minimumLowerContentHeight: CGFloat {
        if isExtraLarge { return 10 }
        return isCompactSixWeekLarge ? 7 : 10
    }

    var holidayFontSize: CGFloat {
        if isExtraLarge { return 9.5 }
        return isCompactSixWeekLarge ? 6.5 : 7.5
    }

    var holidayLineHeight: CGFloat {
        if isExtraLarge { return 12 }
        return isCompactSixWeekLarge ? 7 : 9
    }

    var eventFontSize: CGFloat {
        if isExtraLarge { return 10 }
        return isCompactSixWeekLarge ? 7 : 8.5
    }

    var eventIndicatorHeight: CGFloat {
        if isExtraLarge { return 10 }
        return isCompactSixWeekLarge ? 7 : 8
    }

    var eventLineHeight: CGFloat {
        if isExtraLarge { return 13 }
        return isCompactSixWeekLarge ? 8 : 10
    }

    var overflowFontSize: CGFloat {
        if isExtraLarge { return 9 }
        return isCompactSixWeekLarge ? 6.5 : 7.5
    }

    var multiDayFontSize: CGFloat {
        if isExtraLarge { return 9.5 }
        return isCompactSixWeekLarge ? 6.5 : 8
    }

}

private enum CalendarWidgetDeepLink {
    static func monthURL(for date: Date) -> URL {
        url(host: "month", date: date)
    }

    static func dayURL(for date: Date) -> URL {
        url(host: "day", date: date)
    }

    static func newEventURL(for date: Date) -> URL {
        url(host: "new-event", date: date)
    }

    private static func url(host: String, date: Date) -> URL {
        var components = URLComponents()
        components.scheme = "sscalendar"
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "date", value: dateFormatter.string(from: date))
        ]
        return components.url ?? URL(string: "sscalendar://\(host)")!
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private enum CalendarWidgetColor {
    static func color(for name: String) -> Color {
        switch name {
        case "빨간색", "red": return .red
        case "초록색", "green": return .green
        case "보라색", "purple": return .purple
        case "파란색", "blue": return .blue
        default: return .gray
        }
    }
}
