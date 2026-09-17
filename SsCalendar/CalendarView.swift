import SwiftData
import SwiftUI

struct CalendarView: View {
    @Query(sort: \Event.startDate, order: .forward) private var events: [Event]
    @State private var currentDate = Date()
    @State private var selectedDate = Date()
    @State private var schedulePath: [Date] = []

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.firstWeekday = 1
        return calendar
    }

    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

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

                    Text("\(calendar.component(.month, from: currentDate))월")
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
                DayScheduleView(date: date)
            }
        }
    }

    private var visibleOccurrences: [EventOccurrence] {
        guard
            let firstDate = visibleDates.first,
            let lastDate = visibleDates.last,
            let rangeEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: lastDate
            )
        else {
            return []
        }

        return EventOccurrenceService.occurrences(
            for: events,
            intersecting: DateInterval(start: firstDate, end: rangeEnd),
            calendar: calendar
        )
    }

    private func openSchedule(for date: Date) {
        schedulePath.append(date)
    }

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

private struct CalendarWeek: Identifiable {
    let dates: [Date]

    var id: Date {
        dates[0]
    }
}

private struct CalendarWeekRow: View {
    let week: CalendarWeek
    let occurrences: [EventOccurrence]
    let currentDate: Date
    let selectedDate: Date
    let calendar: Calendar
    let onSelectDate: (Date) -> Void

    private let rowHeight: CGFloat = 100
    private let barHeight: CGFloat = 15
    private let barSpacing: CGFloat = 2
    private let barTopPadding: CGFloat = 42
    private let maximumVisibleSlots = 3

    private var layout: WeekEventLayout {
        WeekEventLayout(
            week: week,
            occurrences: occurrences,
            calendar: calendar,
            maximumVisibleSlots: maximumVisibleSlots
        )
    }

    var body: some View {
        let eventLayout = layout

        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(week.dates, id: \.self) { date in
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
                        showsTitle: segment.showsTitle
                    )
                    .frame(
                        width: cellWidth * CGFloat(
                            segment.endColumn - segment.startColumn + 1
                        ) - 4,
                        height: barHeight
                    )
                    .offset(
                        x: cellWidth * CGFloat(segment.startColumn) + 2,
                        y: barTopPadding + CGFloat(segment.slot) * (
                            barHeight + barSpacing
                        )
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
                                y: barTopPadding + CGFloat(maximumVisibleSlots) * (
                                    barHeight + barSpacing
                                )
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
    let occurrence: EventOccurrence
    let showsTitle: Bool

    private var eventColor: Color {
        EventColor(rawValue: occurrence.event.color)?.color ?? .gray
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(eventColor)

            if showsTitle {
                Text(occurrence.event.title)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct WeekEventLayout {
    let visibleSegments: [WeekEventSegment]
    let overflowCounts: [Int: Int]

    init(
        week: CalendarWeek,
        occurrences: [EventOccurrence],
        calendar: Calendar,
        maximumVisibleSlots: Int
    ) {
        guard
            let weekStart = week.dates.first,
            let weekEnd = week.dates.last
        else {
            visibleSegments = []
            overflowCounts = [:]
            return
        }

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
                showsTitle: eventRange.lowerBound >= weekStart
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

        var slotEndColumns: [Int] = []
        var segments: [WeekEventSegment] = []
        var hiddenCounts: [Int: Int] = [:]

        for candidate in candidates {
            let availableSlot = slotEndColumns.firstIndex {
                candidate.startColumn > $0
            }
            let slot: Int

            if let availableSlot {
                slot = availableSlot
                slotEndColumns[availableSlot] = candidate.endColumn
            } else {
                slot = slotEndColumns.count
                slotEndColumns.append(candidate.endColumn)
            }

            let segment = WeekEventSegment(
                occurrence: candidate.occurrence,
                startColumn: candidate.startColumn,
                endColumn: candidate.endColumn,
                slot: slot,
                showsTitle: candidate.showsTitle
            )

            if slot < maximumVisibleSlots {
                segments.append(segment)
            } else {
                for column in candidate.startColumn...candidate.endColumn {
                    hiddenCounts[column, default: 0] += 1
                }
            }
        }

        visibleSegments = segments
        overflowCounts = hiddenCounts
    }
}

private struct WeekEventCandidate {
    let occurrence: EventOccurrence
    let startColumn: Int
    let endColumn: Int
    let showsTitle: Bool
}

private struct WeekEventSegment: Identifiable {
    let occurrence: EventOccurrence
    let startColumn: Int
    let endColumn: Int
    let slot: Int
    let showsTitle: Bool

    var id: EventOccurrence.ID {
        occurrence.id
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: Event.self, inMemory: true)
}
