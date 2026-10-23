import AppIntents
import SwiftUI
import WidgetKit

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarWidgetEntry

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private var weekdaySymbols: [String] {
        displayCalendar.veryShortStandaloneWeekdaySymbols
    }

    private var displayCalendar: Calendar {
        var calendar = CalendarWidgetCalendar.korean
        calendar.locale = Locale.current
        return calendar
    }

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
                                weekCount: weekCount,
                                textSizeLevel: textSizeLevel
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
        .widgetURL(CalendarWidgetDeepLink.monthURL(dateString: entry.monthDateString))
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

                Link(destination: CalendarWidgetDeepLink.newEventURL(dateString: entry.selectedDateString ?? entry.monthDateString)) {
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
        CalendarWidgetCalendar.monthTitle(year: entry.monthYear, month: entry.monthNumber)
    }

    private func weekdayColor(at index: Int) -> Color {
        if usesColoredWeekends {
            if index == 0 { return .red }
            if index == 6 { return .blue }
        }
        return .secondary
    }

    /// 공휴일 국가가 미국이면 주말도 평일과 같은 색으로 표시한다.
    private var usesColoredWeekends: Bool {
        HolidayCountry.selected(in: HolidayCountry.settingsStore).usesColoredWeekendsForDisplay
    }

    /// 월간 위젯(Large, ExtraLargePortrait) 전용 설정. systemMedium은 이 단계를 적용하지 않는다.
    private var textSizeLevel: Int {
        CalendarTextSizeSetting.level
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
        String(entry.todayDayNumber)
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate = entry.selectedDate else { return false }
        return DeviceCalendar.current.isDate(date, inSameDayAs: selectedDate)
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
    let textSizeLevel: Int

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 7
            let metrics = CalendarWidgetWeekMetrics(
                family: family,
                weekCount: weekCount,
                rowHeight: geometry.size.height,
                columnWidth: columnWidth,
                textSizeLevel: textSizeLevel
            )
            let layout = CalendarWidgetWeekLayout(
                week: week,
                occurrences: occurrences,
                maximumSlots: metrics.maximumMultiDaySlots
            )
            // 단계 3(가장 크게)은 여러 날 일정도 날짜별 점/제목으로 표시하므로, 막대는 그리지 않는다.
            let showsMultiDayBars = textSizeLevel < 3

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(week.days.enumerated()), id: \.element.id) { column, day in
                        CalendarWidgetExpandedDayView(
                            day: day,
                            isSelected: isSelected(day.date),
                            singleDayEvents: singleDayEvents(for: day),
                            hiddenMultiDayCount: showsMultiDayBars ? layout.hiddenCounts[column, default: 0] : 0,
                            multiDaySlotCount: showsMultiDayBars ? layout.occupiedSlotCounts[column, default: 0] : 0,
                            metrics: metrics
                        )
                        .frame(width: columnWidth, height: geometry.size.height)
                    }
                }

                if showsMultiDayBars {
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
    }

    private func singleDayEvents(for day: CalendarWidgetDay) -> [CalendarWidgetEvent] {
        let singleDayIDs = Set(
            occurrences.lazy.filter { !$0.isMultiDay }.map(\.id)
        )
        return day.events.filter { singleDayIDs.contains($0.id) }
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return DeviceCalendar.current.isDate(date, inSameDayAs: selectedDate)
    }
}

/// 단계 3(가장 크게)의 일정 표시 방식. 기본값은 dots이며, 이 값만 바꾸면 위젯 전체에 반영된다.
/// (미리보기에서 두 스타일을 모두 확인할 수 있도록 var로 둔다.)
private enum LargestLevelEventStyle {
    case dots
    case titles
}

private var largestLevelEventStyle: LargestLevelEventStyle = .dots

private struct CalendarWidgetExpandedDayView: View {
    let day: CalendarWidgetDay
    let isSelected: Bool
    let singleDayEvents: [CalendarWidgetEvent]
    let hiddenMultiDayCount: Int
    let multiDaySlotCount: Int
    let metrics: CalendarWidgetWeekMetrics

    private var calendar: Calendar { CalendarWidgetCalendar.korean }

    private var showsHolidayTitle: Bool {
        metrics.textSizeLevel < 2 && day.holidayTitle != nil
    }

    /// 단계별 칸당 최대 보이는 항목 수(막대 슬롯 포함). nil이면 높이로만 제한한다(단계 0).
    private var perCellEventCap: Int? {
        switch metrics.textSizeLevel {
        case 1: return 2
        case 2: return 1
        default: return nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let contentStart = metrics.multiDayStartY
                + CGFloat(multiDaySlotCount)
                * (metrics.multiDayBarHeight + metrics.multiDaySpacing)
            let lunarHeight = lunarText == nil ? 0 : metrics.lunarLineHeight
            let holidayHeight = showsHolidayTitle ? metrics.holidayLineHeight : 0
            let availableHeight = max(
                0,
                geometry.size.height - contentStart - lunarHeight - holidayHeight
            )
            let heightBasedCapacity = max(
                0,
                Int(availableHeight / metrics.eventLineHeight)
            )
            let (visibleEventCount, hiddenCount): (Int, Int) = {
                if metrics.textSizeLevel == 2 {
                    // 단계 2(더 크게): "+n"은 칸당 항목 수 제한에 포함하지 않고 별도 줄로 취급한다.
                    // 막대 1개를 일정 1개로 센다. 높이가 부족하면 일정 1줄 > "+n" 순서로 생략한다.
                    let itemBudget = max(0, 1 - multiDaySlotCount)
                    let visibleCount = min(singleDayEvents.count, itemBudget, heightBasedCapacity)
                    let remainingCount =
                        hiddenMultiDayCount + singleDayEvents.count - visibleCount
                    let eventLineUsed = visibleCount > 0 ? 1 : 0
                    let showsOverflow =
                        remainingCount > 0
                        && (heightBasedCapacity == 0 || heightBasedCapacity - eventLineUsed >= 1)
                    return (visibleCount, showsOverflow ? remainingCount : 0)
                } else {
                    // 단계 0(보통)·1(크게): 기존 방식("+n"도 항목 수에 포함해 자리를 예약) 그대로 유지한다.
                    let eventCapacity: Int = {
                        guard let perCellEventCap else { return heightBasedCapacity }
                        return min(heightBasedCapacity, max(0, perCellEventCap - multiDaySlotCount))
                    }()
                    let initiallyHiddenCount =
                        hiddenMultiDayCount
                        + max(0, singleDayEvents.count - eventCapacity)
                    let visibleCount = min(
                        singleDayEvents.count,
                        initiallyHiddenCount > 0 ? max(0, eventCapacity - 1) : eventCapacity
                    )
                    let hidden =
                        hiddenMultiDayCount + singleDayEvents.count - visibleCount
                    return (visibleCount, hidden)
                }
            }()

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

                    if showsHolidayTitle, let holidayTitle = day.holidayTitle {
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

                    if metrics.textSizeLevel == 3 {
                        switch largestLevelEventStyle {
                        case .dots:
                            eventDots(maxWidth: geometry.size.width - 4)
                        case .titles:
                            eventTitle(linesAvailable: heightBasedCapacity)
                        }
                    } else {
                        ForEach(Array(singleDayEvents.prefix(visibleEventCount))) { event in
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(CalendarWidgetColor.color(for: event.colorName, systemColor: event.systemColor))
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
                }
                .padding(.horizontal, 2)
                .offset(y: contentStart)
            }
        }
        .opacity(day.isCurrentMonth ? 1 : 0.45)
        .background {
            // 단계 3(가장 크게)의 오늘 표시: 원 배지 대신 칸 전체에 연한 파란 배경을 깐다.
            if metrics.textSizeLevel == 3 && day.isToday {
                Color.blue.opacity(0.18)
            }
        }
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
                    .transition(.identity)
            }
        }
    }

    private var dateNumber: some View {
        let isLargestToday = metrics.textSizeLevel == 3 && day.isToday
        return ZStack {
            if day.isToday && metrics.textSizeLevel != 3 {
                Circle()
                    .fill(Color.blue)
                    .frame(width: metrics.dateBadgeSize, height: metrics.dateBadgeSize)
            }

            ImportantMarkerStamp(
                marker: day.importantMarker,
                fontSize: metrics.dateFontSize,
                maxDiameter: metrics.markerDiameterCap,
                maxLineWidth: metrics.markerLineWidthCap,
                minimumLineWidth: 0
            )

            Text(String(day.dayNumber))
                .font(
                    .system(
                        size: metrics.dateFontSize,
                        weight: isLargestToday ? .bold : (day.isToday ? .semibold : .regular)
                    )
                )
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(
                    metrics.textSizeLevel == 3 ? dateColor : (day.isToday ? Color.white : dateColor)
                )
                .frame(width: metrics.dateBadgeSize, height: metrics.dateBadgeSize)
        }
        .frame(maxWidth: .infinity)
    }

    private var dateControls: some View {
        ZStack {
            Link(destination: CalendarWidgetDeepLink.dayURL(dateString: day.dateString)) {
                dateNumber
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(
            Text(
                day.importantMarker == .none
                    ? String(day.dayNumber)
                    : String(day.dayNumber) + ", " + String(localized: "중요한 일정")
            )
        )
    }

    private var lunarText: String? {
        guard LunarDisplaySetting.isEnabled else { return nil }
        guard day.weekday == 1 else {
            return nil
        }
        return LunarCalendarService.lunarDate(year: day.year, month: day.month, day: day.dayNumber)?.displayText
    }

    private var dateColor: Color {
        if day.isHoliday { return .red }
        guard usesColoredWeekends else { return .primary }

        switch day.weekday {
        case 1: return .red
        case 7: return .blue
        default: return .primary
        }
    }

    /// 공휴일 국가가 미국이면 주말도 평일과 같은 색으로 표시한다.
    private var usesColoredWeekends: Bool {
        HolidayCountry.selected(in: HolidayCountry.settingsStore).usesColoredWeekendsForDisplay
    }

    /// 단계 3(가장 크게)의 '점' 스타일. 제목 글자 대신 색깔 점으로 보여준다.
    /// `day.events`는 그 날짜에 걸친 일정을 하루 단위로 1개씩 담고 있어(여러 날 일정도 겹치는 날마다 1개),
    /// 여러 날 일정(막대)도 이 날짜에서는 점 1개로 센다. 점은 칸 너비에 들어가는 만큼만(최대 3개) 보여주고
    /// 나머지는 "+n"으로 합친다.
    private func eventDots(maxWidth: CGFloat) -> some View {
        let dotSize = metrics.eventDotSize
        let spacing: CGFloat = 3
        let maxFitting = max(0, Int((maxWidth + spacing) / (dotSize + spacing)))
        let capacity = min(3, maxFitting)
        let events = day.events
        let visibleCount = min(events.count, capacity)
        let hiddenCount = events.count - visibleCount

        return HStack(spacing: spacing) {
            ForEach(Array(events.prefix(visibleCount))) { event in
                Circle()
                    .fill(CalendarWidgetColor.color(for: event.colorName, systemColor: event.systemColor))
                    .frame(width: dotSize, height: dotSize)
            }

            if hiddenCount > 0 {
                Text("+\(hiddenCount)")
                    .font(.system(size: metrics.overflowFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: metrics.eventDotSize, alignment: .leading)
    }

    /// 단계 3(가장 크게)의 '제목' 스타일. 일정 제목 1개 + "+n"을 보여준다. 글자가 칸을 넘으면 말줄임표.
    /// `day.events`를 그대로 쓰므로(점 스타일과 동일), 여러 날 일정도 막대 없이 날짜당 항목 1개로 센다.
    /// "+n"은 항목 수 제한에 포함하지 않는 별도 줄이다. 높이가 부족하면 일정 1줄 > "+n" 순서로 생략한다.
    private func eventTitle(linesAvailable: Int) -> some View {
        let events = day.events
        let visibleCount = min(events.count, 1, linesAvailable)
        let remainingCount = events.count - visibleCount
        let eventLineUsed = visibleCount > 0 ? 1 : 0
        let showsOverflow =
            remainingCount > 0
            && (linesAvailable == 0 || linesAvailable - eventLineUsed >= 1)
        let hiddenCount = showsOverflow ? remainingCount : 0

        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(events.prefix(visibleCount))) { event in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(CalendarWidgetColor.color(for: event.colorName, systemColor: event.systemColor))
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
    }
}

private struct CalendarWidgetMediumDayView: View {
    let day: CalendarWidgetDay
    let isSelected: Bool

    private var calendar: Calendar { CalendarWidgetCalendar.korean }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Link(destination: CalendarWidgetDeepLink.dayURL(dateString: day.dateString)) {
                    ZStack {
                        if day.isToday {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 17, height: 17)
                        }

                        ImportantMarkerStamp(
                            marker: day.importantMarker,
                            fontSize: 10,
                            maxDiameter: 25,
                            maxLineWidth: 2,
                            minimumLineWidth: 0
                        )

                        Text(String(day.dayNumber))
                            .font(
                                .system(
                                    size: 10,
                                    weight: day.isToday ? .semibold : .regular
                                )
                            )
                            .foregroundStyle(day.isToday ? Color.white : dateColor)
                            .frame(width: 17, height: 17)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(
                    Text(
                        day.importantMarker == .none
                            ? String(day.dayNumber)
                            : String(day.dayNumber) + ", " + String(localized: "중요한 일정")
                    )
                )
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 2) {
                ForEach(Array(day.events.prefix(3))) { event in
                    Circle()
                        .fill(CalendarWidgetColor.color(for: event.colorName, systemColor: event.systemColor))
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
                    .transition(.identity)
            }
        }
    }

    private var dateColor: Color {
        if day.isHoliday { return .red }
        guard usesColoredWeekends else { return .primary }

        switch day.weekday {
        case 1: return .red
        case 7: return .blue
        default: return .primary
        }
    }

    /// 공휴일 국가가 미국이면 주말도 평일과 같은 색으로 표시한다.
    private var usesColoredWeekends: Bool {
        HolidayCountry.selected(in: HolidayCountry.settingsStore).usesColoredWeekends
    }
}

private struct CalendarWidgetMultiDayBar: View {
    let segment: CalendarWidgetWeekSegment
    let metrics: CalendarWidgetWeekMetrics

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    CalendarWidgetColor.color(
                        for: segment.occurrence.colorName,
                        systemColor: segment.occurrence.systemColor
                    )
                )

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

struct CalendarWidgetWeekMetrics {
    let family: WidgetFamily
    let weekCount: Int
    let rowHeight: CGFloat
    let columnWidth: CGFloat
    /// 0 = 보통, 1 = 크게, 2 = 더 크게, 3 = 가장 크게. 날짜 숫자·배지 크기와 일정 표시 방식에 영향을 준다.
    let textSizeLevel: Int

    var isExtraLarge: Bool {
        family == .systemExtraLargePortrait
    }

    var isCompactSixWeekLarge: Bool {
        family == .systemLarge && weekCount >= 6
    }

    /// 단계 0 기준 크기. 아래 dateFontSize/dateBadgeSize가 이 값에 배율을 곱해 키운다.
    private var baseDateFontSize: CGFloat {
        if isExtraLarge { return 14 }
        return isCompactSixWeekLarge ? 11 : 12
    }

    private var baseDateBadgeSize: CGFloat {
        if isExtraLarge { return 24 }
        return isCompactSixWeekLarge ? 17 : 20
    }

    private var sizeMultiplier: CGFloat {
        switch textSizeLevel {
        case 1: return 1.3
        case 2: return 1.7
        default: return 1.0
        }
    }

    /// 실제 칸 높이(rowHeight)를 넘지 않도록 배지 크기 상한을 둔다. 배율은 항상 1.0 이상이라
    /// 상한에 걸려도 단계 0보다 작아지지는 않으므로 단계 순서(보통 < 크게 < 더 크게)는 유지된다.
    private func dateBadgeSize(forMultiplier multiplier: CGFloat) -> CGFloat {
        let scaled = baseDateBadgeSize * multiplier
        let maxAllowed = max(baseDateBadgeSize, rowHeight * 0.45)
        return min(scaled, maxAllowed)
    }

    private func dateFontSize(forBadgeSize badge: CGFloat) -> CGFloat {
        baseDateFontSize * (badge / baseDateBadgeSize)
    }

    var dateBadgeSize: CGFloat {
        if textSizeLevel == 3 { return largestDateBadgeSize }
        return dateBadgeSize(forMultiplier: sizeMultiplier)
    }

    var dateFontSize: CGFloat {
        if textSizeLevel == 3 { return largestDateFontSize }
        return dateFontSize(forBadgeSize: dateBadgeSize)
    }

    /// 단계 3(가장 크게): 두 자리 숫자가 칸 너비(좌우 약 10% 여백 제외)에 맞는 가장 큰 크기를 쓰고,
    /// 칸 높이의 60%를 상한으로 둔다. SF 시스템 폰트 숫자 글리프의 가로폭을 폰트 크기의 약 0.6배로
    /// 근사해 "두 자리 숫자 폭 ≈ 2 × 0.6 × 폰트 크기"로 역산하되, 숫자 조합별 실제 글리프 폭 차이로
    /// 잘리지 않도록 10% 안전 여백을 더 둔다. 단계 2보다 반드시 커지도록 하한도 둔다.
    private var largestDateFontSize: CGFloat {
        let horizontalInset = columnWidth * 0.1
        let availableWidth = max(0, columnWidth - horizontalInset * 2)
        let widthBasedSize = (availableWidth * 0.9) / (2 * 0.6)
        let heightCap = rowHeight * 0.6
        let fitted = min(widthBasedSize, heightCap)
        let level2Font = dateFontSize(forBadgeSize: dateBadgeSize(forMultiplier: 1.7))
        return max(fitted, level2Font + 1)
    }

    /// 숫자가 배지 안에서 잘리지 않도록 폰트 크기보다 10% 여유를 두되, 단계 2 배지보다 반드시 크게 한다.
    private var largestDateBadgeSize: CGFloat {
        let level2Badge = dateBadgeSize(forMultiplier: 1.7)
        return max(largestDateFontSize * 1.1, level2Badge + 1)
    }

    /// 단계 3(가장 크게)의 점 스타일에서 일정 색깔 점의 지름.
    var markerDiameterCap: CGFloat {
        if textSizeLevel == 3 {
            return max(0, columnWidth - 9)
        }
        return min(max(0, columnWidth - 2), dateBadgeSize * 1.3)
    }

    var markerLineWidthCap: CGFloat? {
        textSizeLevel == 3 ? 3 : nil
    }

    var eventDotSize: CGFloat {
        if isExtraLarge { return 7 }
        return isCompactSixWeekLarge ? 4.5 : 5.5
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

// Today 위젯(TodayWidget.swift)도 dayURL(for:)을 재사용하므로 파일 범위보다 넓게 연다.
enum CalendarWidgetDeepLink {
    static func monthURL(dateString: String) -> URL {
        url(host: "month", dateString: dateString)
    }

    static func dayURL(dateString: String) -> URL {
        url(host: "day", dateString: dateString)
    }

    static func newEventURL(dateString: String) -> URL {
        url(host: "new-event", dateString: dateString)
    }

    static func eventURL(
        for eventID: UUID,
        dateString: String,
        occurrenceStartDate: Date,
        originalOccurrenceStartDate: Date
    ) -> URL {
        var components = URLComponents()
        components.scheme = "sscalendar"
        components.host = "event"
        components.queryItems = [
            URLQueryItem(name: "date", value: dateString),
            URLQueryItem(name: "eventID", value: eventID.uuidString),
            URLQueryItem(name: "occurrenceStart", value: String(occurrenceStartDate.timeIntervalSince1970)),
            URLQueryItem(
                name: "originalOccurrenceStart",
                value: String(originalOccurrenceStartDate.timeIntervalSince1970)
            )
        ]
        return components.url ?? dayURL(dateString: dateString)
    }

    private static func url(host: String, dateString: String) -> URL {
        var components = URLComponents()
        components.scheme = "sscalendar"
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "date", value: dateString)
        ]
        return components.url ?? URL(string: "sscalendar://\(host)")!
    }

}

private enum CalendarWidgetColor {
    /// 시스템 캘린더 색이 있으면 그 색을, 없으면 기존 로컬 4색 규칙(colorName)을 사용한다.
    static func color(for name: String, systemColor: CalendarWidgetSystemColor?) -> Color {
        guard let systemColor else {
            return color(for: name)
        }

        return Color(
            .sRGB,
            red: systemColor.red,
            green: systemColor.green,
            blue: systemColor.blue,
            opacity: systemColor.opacity
        )
    }

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

/// 단계 3(가장 크게) 미리보기 전용: 지정한 일정 표시 스타일로 강제한 뒤 항목을 만든다.
/// `largestLevelEventStyle`은 파일 범위 변수라 여기서만 바꿔 볼 수 있다.
private func largestLevelPreviewEntry(style: LargestLevelEventStyle) -> CalendarWidgetEntry {
    largestLevelEventStyle = style
    return calendarTextSizePreviewEntry(level: 3)
}

#Preview("단계 3 가장 크게(점) - 6주 Large", as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    largestLevelPreviewEntry(style: .dots)
}

#Preview("단계 3 가장 크게(점) - Extra Large Portrait", as: .systemExtraLargePortrait) {
    SsCalendarWidget()
} timeline: {
    largestLevelPreviewEntry(style: .dots)
}

#Preview("단계 3 가장 크게(제목) - 6주 Large", as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    largestLevelPreviewEntry(style: .titles)
}

#Preview("단계 3 가장 크게(제목) - Extra Large Portrait", as: .systemExtraLargePortrait) {
    SsCalendarWidget()
} timeline: {
    largestLevelPreviewEntry(style: .titles)
}
