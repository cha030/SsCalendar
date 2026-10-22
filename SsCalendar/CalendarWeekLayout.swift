import Foundation
import SwiftUI
import UIKit

/// WeekEventLayout의 init 파라미터라 유닛 테스트 타깃에서도 생성할 수 있도록 internal로 둔다.
struct CalendarWeek: Identifiable {
    let dates: [Date]

    var id: Date {
        dates[0]
    }
}

/// 주(week) 한 줄의 일정 막대 배치를 계산하는 순수 로직. 뷰(CalendarWeekRow)와 분리해 두면
/// 실제 배치 높이가 렌더링 높이와 어긋나지 않는지 유닛 테스트로 검증할 수 있다.
/// (CalendarView는 private으로 두되, 이 구조체만 테스트 타깃에서 접근할 수 있도록 internal로 둔다.)
struct WeekEventLayout {
    let visibleSegments: [WeekEventSegment]
    let holidayYOffsets: [Int: CGFloat]
    let holidayLineCounts: [Int: Int]
    let overflowCounts: [Int: Int]
    let overflowYOffsets: [Int: CGFloat]

    init(
        week: CalendarWeek,
        occurrences: [CalendarDisplayOccurrence],
        holidaysByDate: [Date: [Holiday]],
        calendar: Calendar,
        rowHeight: CGFloat,
        eventHeight: CGFloat,
        twoLineEventHeight: CGFloat,
        eventSpacing: CGFloat,
        maximumVisibleEventsPerDay: Int,
        /// 단일 날짜 일정 막대에서 제목에 실제로 쓸 수 있는 가로 폭(칸 폭에서 색상 구분선·여백을 뺀 값).
        /// 제목이 이 너비 안에 한 줄로 다 들어가면 세로 공간이 남아도 2줄로 확장하지 않는다.
        singleDayTextWidth: CGFloat,
        holidayTextWidth: CGFloat? = nil
    ) {
        guard
            let weekStart = week.dates.first,
            let weekEnd = week.dates.last
        else {
            visibleSegments = []
            holidayYOffsets = [:]
            holidayLineCounts = [:]
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
                // 이 주(week)에 보이는 막대 조각은 segmentStart(= max(실제 시작일, 이 주의 시작일))
                // 에서 시작하고, 그 조각의 제목은 항상 그 시작 칸에 표시된다. 과거에는 실제 일정
                // 시작일(eventRange.lowerBound)이 "이 주 안"인지로 판단해, 금요일에 시작해 다음 주
                // 까지 이어지는 일정이 둘째 주 일요일 막대에서는 제목이 빠지는 문제가 있었다.
                // 각 주마다 이 함수가 만드는 조각은 항상 하나뿐이라 제목을 매번 보여줘도 중복되지 않는다.
                showsTitle: true,
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

            return first.occurrence.sortStartDate < second.occurrence.sortStartDate
        }

        // 이 주에서 각 날짜(컬럼)가 실제로 몇 개의 일정(단일 날짜 + 그 날을 지나는 여러 날 일정 포함)과
        // 겹치는지 미리 센다. 하루 일정이 1~2개면 기존 Adaptive(여유 있으면 2줄)를 쓰고, 3개 이상이면
        // "표시 개수"를 우선해 단일 날짜 일정 제목을 전부 1줄로 제한한다(제목 길이와 무관하게).
        var totalEventCountByColumn: [Int: Int] = [:]
        for candidate in candidates {
            if candidate.isSingleDay {
                totalEventCountByColumn[candidate.startColumn, default: 0] += 1
            } else {
                for column in candidate.startColumn...candidate.endColumn {
                    totalEventCountByColumn[column, default: 0] += 1
                }
            }
        }
        let denseDayThreshold = 2

        // 공휴일은 여유가 있으면 원래 필요한 줄 수(최대 2줄)를 유지한다. 다만 한 줄로 줄였을 때
        // 실제로 표시 가능한 일정 수가 증가하고, 현재 일정 수가 기존 수용량을 넘는 칸만 1줄로
        // 압축한다. 이 결정값을 CalendarDayCell에도 전달해 렌더링 높이와 배치 높이를 일치시킨다.
        let resolvedHolidayLineCounts = Dictionary(
            uniqueKeysWithValues: week.dates.enumerated().map { column, date in
                let title = CalendarDayContentLayout.holidayTitle(
                    for: holidaysByColumn[column] ?? [],
                    on: date
                )
                let naturalLineCount = CalendarDayContentLayout.holidayLineCount(
                    for: title,
                    availableWidth: holidayTextWidth
                )
                guard naturalLineCount > 1 else { return (column, naturalLineCount) }

                let headerEnd = headerEndYByColumn[column]
                    ?? CalendarDayContentLayout.dateHeaderHeight
                func eventCapacity(holidayLines: Int) -> Int {
                    let availableHeight = rowHeight
                        - headerEnd
                        - CGFloat(holidayLines) * CalendarDayContentLayout.holidayLineHeight
                        - CalendarDayContentLayout.contentSpacing
                    guard availableHeight >= eventHeight else { return 0 }
                    return max(
                        0,
                        Int(floor((availableHeight + eventSpacing) / (eventHeight + eventSpacing)))
                    )
                }

                let naturalCapacity = eventCapacity(holidayLines: naturalLineCount)
                let compressedCapacity = eventCapacity(holidayLines: 1)
                let eventCount = totalEventCountByColumn[column] ?? 0
                let shouldCompress = eventCount > naturalCapacity
                    && compressedCapacity > naturalCapacity
                return (column, shouldCompress ? 1 : naturalLineCount)
            }
        )
        let holidayHeightByColumn = resolvedHolidayLineCounts.mapValues {
            CGFloat($0) * CalendarDayContentLayout.holidayLineHeight
        }

        // 이 칸에 일정이 maximumVisibleEventsPerDay개를 넘으면 "+N" 배지도 한 줄 자리(eventHeight)가
        // 그대로 필요하다. 헤더(최소 38pt) + 4개(56pt)만으로도 이미 94pt라 102pt 칸에 배지 한 줄을
        // 더 넣을 자리가 없다 — 그 상태에서 배지를 억지로 그리면 다음 주 칸과 겹친다(실측으로 확인).
        // 그래서 배지가 필요한 칸은 보여줄 수 있는 한도를 하나 줄여(3개) 배지 자리를 미리 비워 둔다.
        // 정확히 maximumVisibleEventsPerDay개뿐이라 배지가 필요 없는 칸은 그대로 4개를 다 보여준다.
        let effectiveMaxVisibleByColumn: [Int: Int] = Dictionary(
            uniqueKeysWithValues: (0..<week.dates.count).map { column in
                let total = totalEventCountByColumn[column] ?? 0
                let effectiveMax = total > maximumVisibleEventsPerDay
                    ? maximumVisibleEventsPerDay - 1
                    : maximumVisibleEventsPerDay
                return (column, effectiveMax)
            }
        )

        var segments: [WeekEventSegment] = []
        var visibleCounts: [Int: Int] = [:]
        var hiddenCounts: [Int: Int] = [:]

        for candidate in candidates where !candidate.isSingleDay {
            let columns = candidate.startColumn...candidate.endColumn
            let hasReachedLimit = columns.contains { column in
                visibleCounts[column, default: 0] >= (effectiveMaxVisibleByColumn[column] ?? maximumVisibleEventsPerDay)
            }
            var baseY = columns.compactMap {
                headerEndYByColumn[$0]
            }.max() ?? CalendarDayContentLayout.dateHeaderHeight
            baseY += CalendarDayContentLayout.contentSpacing

            // 여러 날에 걸친 일정은 기존 그대로 고정 높이(eventHeight) 1줄만 쓴다(2줄 확장 대상이 아니다).
            guard
                !hasReachedLimit,
                let yOffset = Self.placement(
                    startingAt: baseY,
                    for: candidate,
                    height: eventHeight,
                    among: segments,
                    eventSpacing: eventSpacing,
                    rowHeight: rowHeight
                )
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
                    height: eventHeight,
                    showsTitle: candidate.showsTitle,
                    isSingleDay: false,
                    isTwoLine: false
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
                .map { $0.yOffset + $0.height }
                .max()

            if let multiDayBottom {
                holidayOffsets[column] = multiDayBottom + eventSpacing
            }
        }

        // 같은 날짜에 이후에도 처리할 단일 날짜 일정이 몇 개 더 있는지 미리 세어 둔다.
        // 앞선 일정을 2줄로 늘리기 전에 "뒤에 올 일정들이 최소 1줄 높이로는 반드시 들어갈 공간"을
        // 남겨 둬야, 세로 공간을 욕심내다 뒤 일정이 통째로 +N으로 밀려나는 일이 없다.
        var totalSingleDayCountByColumn: [Int: Int] = [:]
        for candidate in candidates where candidate.isSingleDay {
            totalSingleDayCountByColumn[candidate.startColumn, default: 0] += 1
        }
        var processedSingleDayCountByColumn: [Int: Int] = [:]

        for candidate in candidates where candidate.isSingleDay {
            let column = candidate.startColumn
            let effectiveMax = effectiveMaxVisibleByColumn[column] ?? maximumVisibleEventsPerDay
            let hasReachedLimit =
                visibleCounts[column, default: 0]
                >= effectiveMax

            processedSingleDayCountByColumn[column, default: 0] += 1
            // 실제로 보일 수 있는 한도(effectiveMax — "+N" 배지가 필요한 칸은 그 자리만큼 줄어든다)를
            // 넘는 일정까지 자리를 비워 둘 필요는 없다.
            let visibleTotalForColumn = min(
                totalSingleDayCountByColumn[column] ?? 0,
                effectiveMax
            )
            let remainingAfterThis = max(
                0,
                visibleTotalForColumn - (processedSingleDayCountByColumn[column] ?? 0)
            )
            let reservedForFollowingEvents = CGFloat(remainingAfterThis)
                * (eventHeight + eventSpacing)
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
                .map { $0.yOffset + $0.height }
                .max()

            var baseY: CGFloat
            if let holidayOffset = holidayOffsets[column] {
                baseY = holidayOffset + holidayHeight + eventSpacing
            } else if holidayHeight > 0 {
                baseY = headerEnd + holidayHeight + eventSpacing
            } else if let multiDayBottom {
                baseY = multiDayBottom + eventSpacing
            } else {
                baseY = headerEnd + CalendarDayContentLayout.contentSpacing
            }

            guard !hasReachedLimit else {
                hiddenCounts[column, default: 0] += 1
                continue
            }

            // 하루 일정이 많으면(3개 이상) 제목 길이와 무관하게 전부 1줄로 제한해 "표시 개수"를
            // 우선한다. 1~2개뿐인 날에만, 제목이 실제로 한 줄에 다 들어가지 않을 때 2줄을 검토한다
            // ("발표"처럼 짧은 제목이 불필요하게 2줄 높이를 차지해 아래 일정 자리를 줄이는 문제 방지).
            let isDenseDay = (totalEventCountByColumn[column] ?? 0) > denseDayThreshold
            let needsTwoLines = !isDenseDay && !Self.fitsOnOneLine(
                candidate.occurrence.title,
                within: singleDayTextWidth
            )

            // 제목이 한 줄에 안 들어가고(needsTwoLines) 세로 공간도 충분하면 2줄로, 그렇지 않거나
            // 충돌·침범이 생기면 기존 1줄로 안전하게 되돌아간다. 최종 배치 높이(height)가 곧
            // 렌더링 높이이므로 둘이 어긋날 일이 없다.
            if needsTwoLines, let yOffset = Self.placement(
                startingAt: baseY,
                for: candidate,
                height: twoLineEventHeight,
                among: segments,
                eventSpacing: eventSpacing,
                rowHeight: rowHeight,
                reservedBelow: reservedForFollowingEvents
            ) {
                segments.append(
                    WeekEventSegment(
                        occurrence: candidate.occurrence,
                        startColumn: column,
                        endColumn: column,
                        yOffset: yOffset,
                        height: twoLineEventHeight,
                        showsTitle: candidate.showsTitle,
                        isSingleDay: true,
                        isTwoLine: true
                    )
                )
                visibleCounts[column, default: 0] += 1
            } else if let yOffset = Self.placement(
                startingAt: baseY,
                for: candidate,
                height: eventHeight,
                among: segments,
                eventSpacing: eventSpacing,
                rowHeight: rowHeight,
                reservedBelow: reservedForFollowingEvents
            ) {
                segments.append(
                    WeekEventSegment(
                        occurrence: candidate.occurrence,
                        startColumn: column,
                        endColumn: column,
                        yOffset: yOffset,
                        height: eventHeight,
                        showsTitle: candidate.showsTitle,
                        isSingleDay: true,
                        isTwoLine: false
                    )
                )
                visibleCounts[column, default: 0] += 1
            } else {
                hiddenCounts[column, default: 0] += 1
            }
        }

        var overflowOffsets: [Int: CGFloat] = [:]
        for column in hiddenCounts.keys {
            let headerEnd =
                headerEndYByColumn[column]
                ?? CalendarDayContentLayout.dateHeaderHeight
            let visibleBottom = segments
                .filter { $0.startColumn <= column && $0.endColumn >= column }
                .map { $0.yOffset + $0.height + eventSpacing }
                .max() ?? headerEnd
            let holidayBottom = holidayOffsets[column].map {
                $0 + (holidayHeightByColumn[column] ?? 0) + eventSpacing
            } ?? headerEnd
            // 보이는 일정·공휴일과 겹치지 않는 것이 최우선이다. effectiveMaxVisibleByColumn이 배지
            // 자리를 미리 비워 두므로, 이 값은 평소 rowHeight - eventHeight 안에 자연히 들어온다.
            // (과거엔 여기서 rowHeight - eventHeight로 추가 clamp했는데, 그 상한이 실제 콘텐츠
            // 바닥보다 낮아지는 경우 배지가 보이는 일정과 겹치는 버그가 있었다 — 이제는 애초에
            // 그런 상황이 생기지 않으므로 clamp 없이 콘텐츠 바로 아래에 둔다.)
            overflowOffsets[column] = max(visibleBottom, holidayBottom)
        }

        visibleSegments = segments
        holidayYOffsets = holidayOffsets
        holidayLineCounts = resolvedHolidayLineCounts
        overflowCounts = hiddenCounts
        overflowYOffsets = overflowOffsets
    }

    /// 주어진 너비 안에 제목이 한 줄로 다 들어가는지 실제 폰트 기준으로 판단한다.
    /// 글자 수가 아니라 실제 렌더링 너비로 재므로, 영어처럼 글자 너비가 들쑥날쑥한 경우에도
    /// (공백·단어 길이와 무관하게 "한 줄로 그렸을 때 실제로 차지하는 폭"을 그대로 비교해) 정확하다.
    private static func fitsOnOneLine(_ title: String, within width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        guard !title.isEmpty else { return true }

        let font = UIFont.systemFont(ofSize: CalendarDayContentLayout.singleDayEventFontSize)
        let naturalWidth = (title as NSString).size(withAttributes: [.font: font]).width
        // 부동소수점 오차로 경계값에서 결과가 흔들리지 않도록 아주 작은 여유를 둔다.
        return naturalWidth <= width + 0.5
    }

    /// `availableY`로 충돌 없는 Y를 구한 뒤, 그 높이(+뒤에 올 일정들을 위해 남겨 둘 reservedBelow)로
    /// 칸 아래(rowHeight)까지 실제로 들어가는지 확인한다. 들어가지 않으면 nil을 반환하므로,
    /// 호출하는 쪽은 더 작은 높이로 다시 시도하거나 안 보이는 일정(+N)으로 처리하면 된다.
    private static func placement(
        startingAt initialY: CGFloat,
        for candidate: WeekEventCandidate,
        height: CGFloat,
        among segments: [WeekEventSegment],
        eventSpacing: CGFloat,
        rowHeight: CGFloat,
        reservedBelow: CGFloat = 0
    ) -> CGFloat? {
        let yOffset = Self.availableY(
            startingAt: initialY,
            for: candidate,
            candidateHeight: height,
            among: segments,
            eventSpacing: eventSpacing
        )

        return yOffset + height + reservedBelow <= rowHeight ? yOffset : nil
    }

    /// 이미 배치된 segment들과 겹치지 않는 가장 위쪽 Y를 찾는다. segment마다 실제 높이(height)가
    /// 다를 수 있으므로(1줄/2줄) 비교 시 고정값이 아니라 각 segment의 height를 그대로 쓴다.
    private static func availableY(
        startingAt initialY: CGFloat,
        for candidate: WeekEventCandidate,
        candidateHeight: CGFloat,
        among segments: [WeekEventSegment],
        eventSpacing: CGFloat
    ) -> CGFloat {
        var yOffset = initialY
        var foundCollision = true

        while foundCollision {
            foundCollision = false

            for segment in segments where
                candidate.startColumn <= segment.endColumn &&
                candidate.endColumn >= segment.startColumn {
                let segmentBottom = segment.yOffset + segment.height
                let candidateBottom = yOffset + candidateHeight

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

/// WeekEventLayout.visibleSegments의 원소 타입이라 WeekEventLayout과 같은 접근 수준(internal)이어야 한다.
struct WeekEventSegment: Identifiable {
    let occurrence: CalendarDisplayOccurrence
    let startColumn: Int
    let endColumn: Int
    let yOffset: CGFloat
    /// 실제 렌더링에 쓰이는 높이. 1줄이면 eventHeight, 2줄로 확장되면 twoLineEventHeight와 같다.
    let height: CGFloat
    let showsTitle: Bool
    let isSingleDay: Bool
    /// true면 단일 날짜 일정이 세로 공간 여유로 2줄로 배치된 것이다. 여러 날 일정은 항상 false.
    let isTwoLine: Bool

    var id: String {
        occurrence.id
    }
}
