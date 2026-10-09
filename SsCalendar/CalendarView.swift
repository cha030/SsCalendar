import SwiftData
import SwiftUI

struct CalendarView: View {
    @Query(sort: \Event.startDate, order: .forward) private var events: [Event]
    @State private var currentDate = Date()
    @State private var selectedDate = Date()
    @State private var schedulePath: [Date] = []
    @State private var holidaysByDate: [Date: [Holiday]] = [:]
    @State private var holidayRefreshGeneration = 0
    @State private var isPresentingSettings = false
    @State private var newEventDate: Date?
    @AppStorage(AppTheme.storageKey) private var selectedThemeRawValue = AppTheme.system.rawValue
    @AppStorage(
        SystemCalendarService.isEnabledStorageKey,
        store: SystemCalendarService.settingsStore
    ) private var isSystemCalendarEnabled = false
    @AppStorage(
        HolidayCountry.storageKey,
        store: HolidayCountry.settingsStore
    ) private var holidayCountryRawValue = HolidayCountry.southKorea.rawValue
    @State private var systemOccurrences: [CalendarDisplayOccurrence] = []
    @State private var systemCalendar = SystemCalendarService.shared

    let systemCalendarRefreshGeneration: Int

    init(systemCalendarRefreshGeneration: Int = 0) {
        self.systemCalendarRefreshGeneration = systemCalendarRefreshGeneration
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale.current
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    private var weekdays: [String] {
        calendar.veryShortStandaloneWeekdaySymbols
    }

    var body: some View {
        let occurrences = visibleOccurrences

        NavigationStack(path: $schedulePath) {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        changeMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                    }

                    Text(currentDate.formatted(.dateTime.month(.wide).locale(calendar.locale ?? .current)))
                        .font(.title)
                        .fontWeight(.semibold)
                        .frame(minWidth: 70)

                    Button {
                        changeMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                    }

                    Spacer()

                    Button("오늘") {
                        let today = Date()
                        currentDate = today
                        selectedDate = today
                    }
                    .font(.body)

                    Button {
                        isPresentingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                    }
                    .accessibilityLabel("설정")
                }
                .padding(.horizontal)
                .padding(.top)

                HStack(spacing: 0) {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { index, weekday in
                        Text(weekday)
                            .font(.subheadline)
                            .foregroundStyle(
                                index == 0 ? .red :
                                index == 6 ? .blue :
                                .primary
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)

                Divider()

                VStack(spacing: 0) {
                    ForEach(visibleWeeks) { week in
                        CalendarWeekRow(
                            week: week,
                            occurrences: occurrences,
                            holidaysByDate: holidaysByDate,
                            currentDate: currentDate,
                            selectedDate: selectedDate,
                            calendar: calendar
                        ) { date in
                            if calendar.isDate(date, inSameDayAs: selectedDate) {
                                openSchedule(for: date)
                            } else {
                                selectedDate = date
                            }
                        }
                    }
                }

                Spacer()
            }
            .navigationDestination(for: Date.self) { date in
                DayScheduleView(
                    date: date,
                    systemCalendarRefreshGeneration: systemCalendarRefreshGeneration
                )
            }
            .task(id: holidayFetchKey) {
                await loadHolidays(
                    for: holidayFetchKey.months,
                    country: holidayFetchKey.country
                )
            }
            .task(id: systemCalendarFetchKey) {
                loadSystemOccurrences(for: systemCalendarFetchKey)
            }
            .sheet(isPresented: $isPresentingSettings) {
                ThemeSettingsView(
                    selectedThemeRawValue: $selectedThemeRawValue,
                    holidayCountryRawValue: $holidayCountryRawValue,
                    onHolidayCountryChanged: syncHolidayCountryFromSettings
                )
            }
            .sheet(
                isPresented: Binding(
                    get: { newEventDate != nil },
                    set: { if !$0 { newEventDate = nil } }
                )
            ) {
                if let newEventDate {
                    NavigationStack {
                        EventEditorView(date: newEventDate)
                    }
                }
            }
            .onOpenURL(perform: handleDeepLink)
            .onChange(of: holidayCountryRawValue) { _, _ in
                holidaysByDate = [:]
            }
        }
    }

    private var holidayCountry: HolidayCountry {
        HolidayCountry(rawValue: holidayCountryRawValue) ?? .southKorea
    }

    private var holidayFetchKey: HolidayFetchKey {
        HolidayFetchKey(
            country: holidayCountry,
            months: visibleHolidayMonths,
            refreshGeneration: holidayRefreshGeneration
        )
    }

    private func syncHolidayCountryFromSettings() {
        holidaysByDate = [:]
        holidayRefreshGeneration += 1
    }

    private var visibleInterval: DateInterval? {
        guard
            let firstDate = visibleDates.first,
            let lastDate = visibleDates.last,
            let rangeEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: lastDate
            )
        else {
            return nil
        }

        return DateInterval(start: firstDate, end: rangeEnd)
    }

    /// 로컬(SwiftData) 반복 전개 결과와 시스템 캘린더 일정을 표시 모델 기준으로 합친다.
    private var visibleOccurrences: [CalendarDisplayOccurrence] {
        guard let visibleInterval else {
            return []
        }

        let localOccurrences = EventOccurrenceService.occurrences(
            for: events,
            intersecting: visibleInterval,
            calendar: calendar
        )
        .map { CalendarDisplayOccurrence(local: $0) }

        return CalendarDisplayOccurrence.merged(
            local: localOccurrences,
            system: isSystemCalendarEnabled ? systemOccurrences : []
        )
    }

    private var systemCalendarFetchKey: SystemCalendarFetchKey {
        SystemCalendarFetchKey(
            interval: visibleInterval,
            isEnabled: isSystemCalendarEnabled,
            changeToken: systemCalendar.changeToken,
            refreshGeneration: systemCalendarRefreshGeneration
        )
    }

    private func loadSystemOccurrences(for key: SystemCalendarFetchKey) {
        guard key.isEnabled, let interval = key.interval else {
            systemOccurrences = []
            return
        }

        systemOccurrences = systemCalendar.occurrences(in: interval)
    }

    private var visibleHolidayMonths: [HolidayMonth] {
        let months = visibleDates.compactMap { date -> HolidayMonth? in
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else {
                return nil
            }
            return HolidayMonth(year: year, month: month)
        }

        return Array(Set(months)).sorted()
    }

    @MainActor
    private func loadHolidays(
        for months: [HolidayMonth],
        country: HolidayCountry
    ) async {
        var loadedByDate: [Date: [Holiday]] = [:]

        for month in months {
            guard !Task.isCancelled else { return }

            do {
                let holidays = try await HolidayService.shared.holidays(
                    for: month,
                    country: country
                )
                for holiday in holidays where holiday.isHoliday {
                    let day = calendar.startOfDay(for: holiday.date)
                    loadedByDate[day, default: []].append(holiday)
                }
            } catch {
                // Holiday data is optional. Calendar and event features stay available.
                continue
            }
        }

        guard !Task.isCancelled,
              country == holidayCountry,
              months == visibleHolidayMonths else { return }
        holidaysByDate = loadedByDate
    }

    private func openSchedule(for date: Date) {
        schedulePath.append(date)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "sscalendar" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard
            let dateString = components?.queryItems?.first(where: { $0.name == "date" })?.value,
            let date = Self.deepLinkDateFormatter.date(from: dateString)
        else {
            return
        }

        currentDate = date
        selectedDate = date

        switch url.host {
        case "month":
            schedulePath.removeAll()
        case "day":
            schedulePath = [date]
        case "new-event":
            schedulePath.removeAll()
            newEventDate = date
        default:
            break
        }
    }

    private static let deepLinkDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func changeMonth(by value: Int) {
        if let newDate = calendar.date(
            byAdding: .month,
            value: value,
            to: currentDate
        ) {
            currentDate = newDate
        }
    }

    private var visibleWeeks: [CalendarWeek] {
        let dates = visibleDates
        var weeks: [CalendarWeek] = []
        var startIndex = 0

        while startIndex + 7 <= dates.count {
            let weekDates = Array(dates[startIndex..<(startIndex + 7)])
            weeks.append(CalendarWeek(dates: weekDates))
            startIndex += 7
        }

        return weeks
    }

    private var visibleDates: [Date] {
        guard
            let monthInterval = calendar.dateInterval(
                of: .month,
                for: currentDate
            )
        else {
            return []
        }

        let firstDay = monthInterval.start

        guard
            let firstWeek = calendar.dateInterval(
                of: .weekOfMonth,
                for: firstDay
            )
        else {
            return []
        }

        guard
            let lastDay = calendar.date(
                byAdding: .day,
                value: -1,
                to: monthInterval.end
            )
        else {
            return []
        }

        guard
            let lastWeek = calendar.dateInterval(
                of: .weekOfMonth,
                for: lastDay
            )
        else {
            return []
        }

        var dates: [Date] = []
        var date = firstWeek.start

        while date < lastWeek.end {
            dates.append(date)

            guard let nextDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: date
            ) else {
                break
            }

            date = nextDate
        }

        return dates
    }
}

private struct SystemCalendarFetchKey: Equatable {
    let interval: DateInterval?
    let isEnabled: Bool
    let changeToken: Int
    let refreshGeneration: Int
}

private struct CalendarWeek: Identifiable {
    let dates: [Date]

    var id: Date {
        dates[0]
    }
}

private struct CalendarWeekRow: View {
    let week: CalendarWeek
    let occurrences: [CalendarDisplayOccurrence]
    let holidaysByDate: [Date: [Holiday]]
    let currentDate: Date
    let selectedDate: Date
    let calendar: Calendar
    let onSelectDate: (Date) -> Void

    private let rowHeight = CalendarDayContentLayout.cellHeight
    private let eventHeight: CGFloat = 13
    private let eventSpacing: CGFloat = 1
    private let maximumVisibleEventsPerDay = 3

    private var layout: WeekEventLayout {
        WeekEventLayout(
            week: week,
            occurrences: occurrences,
            holidaysByDate: holidaysByDate,
            calendar: calendar,
            rowHeight: rowHeight,
            eventHeight: eventHeight,
            eventSpacing: eventSpacing,
            maximumVisibleEventsPerDay: maximumVisibleEventsPerDay
        )
    }

    var body: some View {
        let eventLayout = layout

        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(
                    Array(week.dates.enumerated()),
                    id: \.element
                ) { column, date in
                    CalendarDayCell(
                        date: date,
                        isCurrentMonth: calendar.isDate(
                            date,
                            equalTo: currentDate,
                            toGranularity: .month
                        ),
                        isToday: calendar.isDateInToday(date),
                        isSelected: calendar.isDate(
                            date,
                            inSameDayAs: selectedDate
                        ),
                        holidays: holidaysByDate[
                            calendar.startOfDay(for: date)
                        ] ?? [],
                        holidayTopOffset: eventLayout.holidayYOffsets[column],
                        calendar: calendar
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectDate(date)
                    }
                }
            }

            GeometryReader { geometry in
                let cellWidth = geometry.size.width / 7

                ForEach(eventLayout.visibleSegments) { segment in
                    CalendarEventBar(
                        occurrence: segment.occurrence,
                        showsTitle: segment.showsTitle,
                        isSingleDay: segment.isSingleDay
                    )
                    .frame(
                        width: cellWidth * CGFloat(
                            segment.endColumn - segment.startColumn + 1
                        ) - 4,
                        height: eventHeight
                    )
                    .offset(
                        x: cellWidth * CGFloat(segment.startColumn) + 2,
                        y: segment.yOffset
                    )
                }

                ForEach(eventLayout.overflowCounts.keys.sorted(), id: \.self) { column in
                    if let count = eventLayout.overflowCounts[column] {
                        Text("+\(count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(
                                width: cellWidth - 8,
                                alignment: .leading
                            )
                            .offset(
                                x: cellWidth * CGFloat(column) + 4,
                                y: eventLayout.overflowYOffsets[column]
                                    ?? rowHeight - eventHeight
                            )
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: rowHeight)
    }
}

private struct CalendarEventBar: View {
    let occurrence: CalendarDisplayOccurrence
    let showsTitle: Bool
    let isSingleDay: Bool

    private var eventColor: Color {
        occurrence.color
    }

    var body: some View {
        if isSingleDay {
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(eventColor)
                    .frame(width: 3)

                Text(occurrence.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(eventColor)

                if showsTitle {
                    Text(occurrence.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 4)
                }
            }
        }
    }
}

private struct WeekEventLayout {
    let visibleSegments: [WeekEventSegment]
    let holidayYOffsets: [Int: CGFloat]
    let overflowCounts: [Int: Int]
    let overflowYOffsets: [Int: CGFloat]

    init(
        week: CalendarWeek,
        occurrences: [CalendarDisplayOccurrence],
        holidaysByDate: [Date: [Holiday]],
        calendar: Calendar,
        rowHeight: CGFloat,
        eventHeight: CGFloat,
        eventSpacing: CGFloat,
        maximumVisibleEventsPerDay: Int
    ) {
        guard
            let weekStart = week.dates.first,
            let weekEnd = week.dates.last
        else {
            visibleSegments = []
            holidayYOffsets = [:]
            overflowCounts = [:]
            overflowYOffsets = [:]
            return
        }

        let holidaysByColumn = Dictionary(
            uniqueKeysWithValues: week.dates.enumerated().map { column, date in
                (
                    column,
                    holidaysByDate[calendar.startOfDay(for: date)] ?? []
                )
            }
        )
        let headerEndYByColumn = Dictionary(
            uniqueKeysWithValues: week.dates.enumerated().map { column, date in
                (
                    column,
                    CalendarDayContentLayout.headerEndY(
                        for: date,
                        calendar: calendar
                    )
                )
            }
        )
        let holidayHeightByColumn = Dictionary(
            uniqueKeysWithValues: week.dates.enumerated().map { column, date in
                (
                    column,
                    CalendarDayContentLayout.holidayHeight(
                        for: date,
                        holidays: holidaysByColumn[column] ?? []
                    )
                )
            }
        )

        let candidates = occurrences.compactMap { occurrence -> WeekEventCandidate? in
            let eventRange = occurrence.occupiedDayRange(calendar: calendar)

            guard
                eventRange.upperBound >= weekStart,
                eventRange.lowerBound <= weekEnd
            else {
                return nil
            }

            let segmentStart = max(eventRange.lowerBound, weekStart)
            let segmentEnd = min(eventRange.upperBound, weekEnd)
            let startColumn = calendar.dateComponents(
                [.day],
                from: weekStart,
                to: segmentStart
            ).day ?? 0
            let endColumn = calendar.dateComponents(
                [.day],
                from: weekStart,
                to: segmentEnd
            ).day ?? startColumn

            return WeekEventCandidate(
                occurrence: occurrence,
                startColumn: startColumn,
                endColumn: endColumn,
                showsTitle: eventRange.lowerBound >= weekStart,
                isSingleDay: calendar.isDate(
                    eventRange.lowerBound,
                    inSameDayAs: eventRange.upperBound
                )
            )
        }
        .sorted { first, second in
            if first.startColumn != second.startColumn {
                return first.startColumn < second.startColumn
            }

            if first.occurrence.isAllDay != second.occurrence.isAllDay {
                return first.occurrence.isAllDay
            }

            if first.endColumn != second.endColumn {
                return first.endColumn > second.endColumn
            }

            return first.occurrence.startDate < second.occurrence.startDate
        }

        var segments: [WeekEventSegment] = []
        var visibleCounts: [Int: Int] = [:]
        var hiddenCounts: [Int: Int] = [:]

        for candidate in candidates where !candidate.isSingleDay {
            let columns = candidate.startColumn...candidate.endColumn
            let hasReachedLimit = columns.contains {
                visibleCounts[$0, default: 0] >= maximumVisibleEventsPerDay
            }
            var yOffset = columns.compactMap {
                headerEndYByColumn[$0]
            }.max() ?? CalendarDayContentLayout.dateHeaderHeight
            yOffset += CalendarDayContentLayout.contentSpacing
            yOffset = Self.availableY(
                startingAt: yOffset,
                for: candidate,
                among: segments,
                eventHeight: eventHeight,
                eventSpacing: eventSpacing
            )

            guard
                !hasReachedLimit,
                yOffset + eventHeight <= rowHeight
            else {
                for column in columns {
                    hiddenCounts[column, default: 0] += 1
                }
                continue
            }

            segments.append(
                WeekEventSegment(
                    occurrence: candidate.occurrence,
                    startColumn: candidate.startColumn,
                    endColumn: candidate.endColumn,
                    yOffset: yOffset,
                    showsTitle: candidate.showsTitle,
                    isSingleDay: false
                )
            )
            for column in columns {
                visibleCounts[column, default: 0] += 1
            }
        }

        var holidayOffsets: [Int: CGFloat] = [:]
        for column in week.dates.indices {
            guard (holidayHeightByColumn[column] ?? 0) > 0 else {
                continue
            }

            let multiDayBottom = segments
                .filter {
                    !$0.isSingleDay &&
                    $0.startColumn <= column &&
                    $0.endColumn >= column
                }
                .map { $0.yOffset + eventHeight }
                .max()

            if let multiDayBottom {
                holidayOffsets[column] = multiDayBottom + eventSpacing
            }
        }

        for candidate in candidates where candidate.isSingleDay {
            let column = candidate.startColumn
            let hasReachedLimit =
                visibleCounts[column, default: 0]
                >= maximumVisibleEventsPerDay
            let headerEnd =
                headerEndYByColumn[column]
                ?? CalendarDayContentLayout.dateHeaderHeight
            let holidayHeight = holidayHeightByColumn[column] ?? 0
            let multiDayBottom = segments
                .filter {
                    !$0.isSingleDay &&
                    $0.startColumn <= column &&
                    $0.endColumn >= column
                }
                .map { $0.yOffset + eventHeight }
                .max()

            var yOffset: CGFloat
            if let holidayOffset = holidayOffsets[column] {
                yOffset = holidayOffset + holidayHeight + eventSpacing
            } else if holidayHeight > 0 {
                yOffset = headerEnd + holidayHeight + eventSpacing
            } else if let multiDayBottom {
                yOffset = multiDayBottom + eventSpacing
            } else {
                yOffset = headerEnd + CalendarDayContentLayout.contentSpacing
            }

            yOffset = Self.availableY(
                startingAt: yOffset,
                for: candidate,
                among: segments,
                eventHeight: eventHeight,
                eventSpacing: eventSpacing
            )

            guard
                !hasReachedLimit,
                yOffset + eventHeight <= rowHeight
            else {
                hiddenCounts[column, default: 0] += 1
                continue
            }

            segments.append(
                WeekEventSegment(
                    occurrence: candidate.occurrence,
                    startColumn: column,
                    endColumn: column,
                    yOffset: yOffset,
                    showsTitle: candidate.showsTitle,
                    isSingleDay: true
                )
            )
            visibleCounts[column, default: 0] += 1
        }

        var overflowOffsets: [Int: CGFloat] = [:]
        for column in hiddenCounts.keys {
            let headerEnd =
                headerEndYByColumn[column]
                ?? CalendarDayContentLayout.dateHeaderHeight
            let visibleBottom = segments
                .filter { $0.startColumn <= column && $0.endColumn >= column }
                .map { $0.yOffset + eventHeight + eventSpacing }
                .max() ?? headerEnd
            let holidayBottom = holidayOffsets[column].map {
                $0 + (holidayHeightByColumn[column] ?? 0) + eventSpacing
            } ?? headerEnd
            overflowOffsets[column] = min(
                max(visibleBottom, holidayBottom),
                rowHeight - eventHeight
            )
        }

        visibleSegments = segments
        holidayYOffsets = holidayOffsets
        overflowCounts = hiddenCounts
        overflowYOffsets = overflowOffsets
    }

    private static func availableY(
        startingAt initialY: CGFloat,
        for candidate: WeekEventCandidate,
        among segments: [WeekEventSegment],
        eventHeight: CGFloat,
        eventSpacing: CGFloat
    ) -> CGFloat {
        var yOffset = initialY
        var foundCollision = true

        while foundCollision {
            foundCollision = false

            for segment in segments where
                candidate.startColumn <= segment.endColumn &&
                candidate.endColumn >= segment.startColumn {
                let segmentBottom = segment.yOffset + eventHeight
                let candidateBottom = yOffset + eventHeight

                if yOffset < segmentBottom + eventSpacing &&
                    candidateBottom + eventSpacing > segment.yOffset {
                    yOffset = segmentBottom + eventSpacing
                    foundCollision = true
                }
            }
        }

        return yOffset
    }
}

private struct WeekEventCandidate {
    let occurrence: CalendarDisplayOccurrence
    let startColumn: Int
    let endColumn: Int
    let showsTitle: Bool
    let isSingleDay: Bool
}

private struct WeekEventSegment: Identifiable {
    let occurrence: CalendarDisplayOccurrence
    let startColumn: Int
    let endColumn: Int
    let yOffset: CGFloat
    let showsTitle: Bool
    let isSingleDay: Bool

    var id: String {
        occurrence.id
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: Event.self, inMemory: true)
}
