import SwiftUI

struct CalendarWeekRow: View {
    let week: CalendarWeek
    let occurrences: [CalendarDisplayOccurrence]
    let holidaysByDate: [Date: [Holiday]]
    let currentDate: Date
    let selectedDate: Date
    let calendar: Calendar
    let onSelectDate: (Date) -> Void

    private let rowHeight = CalendarDayContentLayout.cellHeight
    private let eventHeight: CGFloat = 13
    // 단일 날짜 일정이 2줄로 확장될 때의 높이. 폰트 크기(11pt)는 그대로 두고 줄 수만 늘린다.
    // 11pt 시스템 폰트의 실제 줄 높이는 약 13.1pt라 eventHeight*2(26)로는 2번째 줄 아래가
    // 미세하게 잘릴 수 있어 1pt 여유를 둔다.
    private let twoLineEventHeight: CGFloat = 27
    private let eventSpacing: CGFloat = 1
    // 세로 공간이 허용하는 한 하루 최대 4개까지 보여준다(공간이 부족하면 배치 엔진이 자연히
    // 3개 이하로 줄이고 나머지를 +N으로 넘긴다 — WeekEventLayout의 placement 적합성 검사 참고).
    private let maximumVisibleEventsPerDay = 4

    static func importantMarker(
        for date: Date,
        occurrences: [CalendarDisplayOccurrence],
        calendar: Calendar
    ) -> ImportantMarker {
        occurrences
            .filter { occurrence in
                guard !occurrence.isSystem,
                      occurrence.importantMarker != .none else {
                    return false
                }
                let startDay = occurrence.occupiedDayRange(calendar: calendar).lowerBound
                return calendar.isDate(startDay, inSameDayAs: date)
            }
            .sorted { first, second in
                if first.createdAt != second.createdAt {
                    return first.createdAt < second.createdAt
                }
                return first.id < second.id
            }
            .first?.importantMarker ?? .none
    }

    /// 단일 날짜 일정이 2줄로 확장돼도 되는지는 "실제 제목이 한 줄에 다 들어가는 너비"를 알아야
    /// 판단할 수 있다. 그 너비는 칸 폭(cellWidth)에서 정해지므로, 이 계산을 GeometryReader 안에서
    /// 실제 cellWidth를 구한 뒤에 한다(바깥에서 미리 계산해 두면 폭을 알 수 없다).
    private func layout(cellWidth: CGFloat) -> WeekEventLayout {
        let singleDayTextWidth = max(
            0,
            cellWidth - CalendarDayContentLayout.singleDayEventChromeWidth
        )

        return WeekEventLayout(
            week: week,
            occurrences: occurrences,
            holidaysByDate: holidaysByDate,
            calendar: calendar,
            rowHeight: rowHeight,
            eventHeight: eventHeight,
            twoLineEventHeight: twoLineEventHeight,
            eventSpacing: eventSpacing,
            maximumVisibleEventsPerDay: maximumVisibleEventsPerDay,
            singleDayTextWidth: singleDayTextWidth,
            holidayTextWidth: max(
                0,
                cellWidth - CalendarDayContentLayout.holidayHorizontalPadding
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / 7
            let eventLayout = layout(cellWidth: cellWidth)

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
                            holidayTextWidth: max(
                                0,
                                cellWidth - CalendarDayContentLayout.holidayHorizontalPadding
                            ),
                            displayedHolidayLineCount: eventLayout.holidayLineCounts[column],
                            calendar: calendar,
                            importantMarker: Self.importantMarker(
                                for: date,
                                occurrences: occurrences,
                                calendar: calendar
                            )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectDate(date)
                        }
                    }
                }

                Group {
                    ForEach(eventLayout.visibleSegments) { segment in
                        CalendarEventBar(
                            occurrence: segment.occurrence,
                            showsTitle: segment.showsTitle,
                            isSingleDay: segment.isSingleDay,
                            isTwoLine: segment.isTwoLine
                        )
                        .frame(
                            width: cellWidth * CGFloat(
                                segment.endColumn - segment.startColumn + 1
                            ) - 4,
                            // 2줄로 확장된 세그먼트는 실제 렌더링 높이도 같이 늘려 배치 계산과 어긋나지 않게 한다.
                            height: segment.height
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
        }
        .frame(height: rowHeight)
    }
}

struct CalendarEventBar: View {
    let occurrence: CalendarDisplayOccurrence
    let showsTitle: Bool
    let isSingleDay: Bool
    /// true면 WeekEventLayout이 이 날짜에 세로 공간이 충분하다고 판단해 2줄 높이로 배치한 것이다.
    /// 여러 날에 걸친 일정(else 분기)에는 적용하지 않는다.
    let isTwoLine: Bool

    private var eventColor: Color {
        occurrence.color
    }

    var body: some View {
        if isSingleDay {
            // `Spacer`로 Text의 너비를 간접적으로 정해주던 기존 방식은 lineLimit(1)에서는 문제없이
            // 동작했지만, lineLimit(2)를 주면 HStack이 Text의 "이상적인 너비"를 (2줄로 나눠 쓸 수
            // 있다고 가정해) 더 좁게 계산해 Spacer와의 너비 배분이 달라진다. 그 결과 칸 높이(색상
            // 막대)는 2줄만큼 늘어나지만 정작 Text는 실제로 쓸 수 있는 것보다 좁은 너비를 받아
            // 오히려 더 심하게 잘려 보였다(2줄로 줄바꿈되지 않고 1줄로 과도하게 말줄임됨).
            // Text에 직접 `.frame(maxWidth: .infinity, alignment: .leading)`을 줘서 남는 너비를
            // 명확하게 모두 받게 하고, `.fixedSize(horizontal: false, vertical: true)`로 그 너비
            // 안에서 필요한 줄 수(최대 2줄)만큼의 실제 높이를 그대로 보고하도록 고정한다.
            HStack(alignment: isTwoLine ? .top : .center, spacing: 3) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(eventColor)
                    .frame(width: 3)

                // 폰트 크기(11pt)와 minimumScaleFactor 없는 점은 1줄일 때와 동일하게 유지하고,
                // 세로 공간이 충분할 때만 줄 수를 2로 늘린다.
                Text(occurrence.title)
                    .font(.system(size: CalendarDayContentLayout.singleDayEventFontSize))
                    .foregroundStyle(.primary)
                    .lineLimit(isTwoLine ? 2 : 1)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
