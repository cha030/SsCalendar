import SwiftData
import SwiftUI
import UIKit

struct CalendarView: View {
    @Query(sort: \Event.startDate, order: .forward) private var events: [Event]
    /// 반복 일정의 개별 수정·삭제 예외(Step 5-2). 월간 달력 표시에도 반영한다.
    @Query private var occurrenceExceptions: [EventOccurrenceException]
    @State private var currentDate = Date()
    @State private var selectedDate = Date()
    @State private var schedulePath: [Date] = []
    @State private var holidaysByDate: [Date: [Holiday]] = [:]
    @State private var holidayRefreshGeneration = 0
    @State private var isPresentingSettings = false
    @State private var newEventDate: Date?
    @State private var isPresentingYearCalendar = false
    @State private var monthChangeDirection: MonthChangeDirection = .toNextMonth
    /// 헤더 왼쪽 연도 칸·오른쪽 오늘·설정 버튼 칸에 똑같이 적용하는 고정 너비. 두 칸이 같은
    /// 너비여야 그 사이(가운데)가 화면 전체 기준으로 정확한 중앙이 된다(아래 body 주석 참고).
    private static let headerSideSlotWidth: CGFloat = 100
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
                // 좌우 화살표를 없애고 스와이프로 대체했다(아래 monthSwipeGesture). 왼쪽엔 작은
                // 글자의 연도("2026년", 탭하면 연간 달력), 가운데엔 크고 굵은 월 제목("10월")을
                // 화면 전체 폭 기준으로 정확히 중앙에, 오른쪽엔 기존 오늘·설정 버튼을 둔다.
                // 왼쪽 연도 칸과 오른쪽 버튼 칸의 너비를 똑같이(headerSideSlotWidth) 고정해 둬야
                // 그 사이(가운데)가 실제로 화면 중앙이 된다 — 두 칸이 다른 너비면 중앙이 어긋난다.
                HStack(spacing: 0) {
                    Text(currentDate.formatted(.dateTime.year().locale(calendar.locale ?? .current)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: Self.headerSideSlotWidth, alignment: .leading)
                        // 연도 자릿수가 바뀌어도(스와이프로 달 넘기다 연말·연초를 지날 때)
                        // 흔들리지 않도록 DayScheduleView 날짜 제목과 같은 이유로 애니메이션을 끈다.
                        .animation(nil, value: currentDate)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isPresentingYearCalendar = true
                        }

                    Spacer(minLength: 0)

                    // 긴 영어 월 이름("September")도 왼쪽 연도 칸·오른쪽 버튼 칸과 겹치지
                    // 않도록 한 줄로 고정하고, 공간이 부족할 때만 minimumScaleFactor로 줄인다.
                    Text(currentDate.formatted(.dateTime.month(.wide).locale(calendar.locale ?? .current)))
                        .font(.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                        .animation(nil, value: currentDate)

                    Spacer(minLength: 0)

                    trailingButtons
                        .frame(width: Self.headerSideSlotWidth, alignment: .trailing)
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

                // 달이 실제로 바뀔 때만(날짜 선택만으로는 재생되지 않게 currentMonthStart로 식별)
                // 스와이프 방향에 맞춰 가볍게 슬라이드 전환한다.
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
                .id(currentMonthStart)
                .transition(monthGridTransition)

                Spacer()
            }
            // 월간 달력 어디를 스와이프해도 다음/이전 달로 이동한다. 날짜 칸의 onTapGesture는
            // 최소 이동 거리(24pt) 없는 순수 탭이라 이 DragGesture와 겹치지 않고, simultaneousGesture라
            // CalendarWeekRow 내부의 다른 제스처도 그대로 동작한다(DayScheduleView와 같은 방식).
            .simultaneousGesture(monthSwipeGesture)
            .navigationDestination(for: Date.self) { date in
                DayScheduleView(
                    date: date,
                    systemCalendarRefreshGeneration: systemCalendarRefreshGeneration,
                    // 하루 화면 안에서 좌우로 스와이프해 다른 날짜로 넘어가면, 월간 달력으로 돌아왔을 때
                    // 그 날짜가 선택돼 있고(달이 바뀌었다면 그 달이) 보이도록 여기서 같이 갱신해 둔다.
                    onNavigateToDate: { navigatedDate in
                        currentDate = navigatedDate
                        selectedDate = navigatedDate
                    }
                )
                // NavigationStack이 schedulePath를 교체(예: 위젯 딥링크로 [이전 날짜] → [새 날짜])할 때,
                // 배열 모양(길이 1 → 1)이 그대로라 SwiftUI가 이전 목적지 화면의 인스턴스·@State를
                // 재사용해 버리는 경우가 있었다(DayScheduleView의 _currentDate = State(initialValue:)가
                // 다시 적용되지 않아 이전 날짜가 그대로 남는 문제). date를 명시적 식별자로 지정해
                // 날짜가 다르면 항상 완전히 새 화면으로 취급되게 한다 — 날짜 선택·위젯 이동 오류의
                // 근본 원인(목적지 뷰 상태 재사용)을 직접 없애는 수정이다.
                .id(date)
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
            // 연도 좌우 스와이프가 월간 화면(DayScheduleView)의 날짜 스와이프나 iOS 기본 엣지 뒤로
            // 가기 제스처와 섞이지 않도록, NavigationStack에 push하지 않고 완전히 분리된 전체 화면
            // 모달로 띄운다(fullScreenCover는 sheet와 달리 기본 인터랙티브 닫기 제스처가 없다).
            .fullScreenCover(isPresented: $isPresentingYearCalendar) {
                YearCalendarView(
                    initialYear: calendar.component(.year, from: currentDate),
                    calendar: calendar,
                    onSelectMonth: { year, month in
                        // 선택한 연도·월의 1일로 currentDate(표시 중인 달)만 갱신한다.
                        // selectedDate(사용자가 고른 날짜)는 건드리지 않는다 — 1일을 강제 선택하지
                        // 않기 위함이다.
                        if let newDate = calendar.date(
                            from: DateComponents(year: year, month: month, day: 1)
                        ) {
                            currentDate = newDate
                        }
                        isPresentingYearCalendar = false
                    },
                    onClose: {
                        isPresentingYearCalendar = false
                    }
                )
            }
            .onOpenURL(perform: handleDeepLink)
            .onChange(of: holidayCountryRawValue) { _, _ in
                holidaysByDate = [:]
            }
        }
    }

    /// 헤더 오른쪽의 "오늘·설정" 버튼 묶음. 왼쪽 투명 자리 표시자와 똑같은 뷰를 그대로 재사용해,
    /// 제목 묶음이 실제로 헤더 가운데에 오도록 만드는 데 쓴다(위 body의 주석 참고).
    private var trailingButtons: some View {
        HStack(spacing: 8) {
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
            calendar: calendar,
            exceptions: occurrenceExceptions
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
        // 위젯 등 외부에서 들어온 딥링크는 그 시점에 확정된 대상으로 정확히 이동해야 하므로,
        // 이전에 남아 있을 수 있는 "새 일정 추가" 상태부터 먼저 비운다(아래 switch에서
        // new-event면 다시 채운다).
        newEventDate = nil

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
        guard let newDate = calendar.date(
            byAdding: .month,
            value: value,
            to: currentDate
        ) else { return }

        monthChangeDirection = value > 0 ? .toNextMonth : .toPreviousMonth
        withAnimation(.easeInOut(duration: 0.22)) {
            currentDate = newDate
        }
    }

    /// 월간 달력 좌우 스와이프. DayScheduleView의 날짜 스와이프와 같은 기준(최소 이동 거리·
    /// 수평/수직 비율)으로 세로 스크롤이나 날짜 칸 탭과 오인식되지 않게 한다. CalendarView는
    /// NavigationStack의 루트 화면이라(뒤로 갈 화면이 없다) DayScheduleView에서 뒀던 엣지
    /// 뒤로가기 제스처 회피 처리는 필요 없다.
    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 60, abs(horizontal) > abs(vertical) * 2 else { return }
                changeMonth(by: horizontal < 0 ? 1 : -1)
            }
    }

    private var monthGridTransition: AnyTransition {
        let insertionEdge: Edge = monthChangeDirection == .toNextMonth ? .trailing : .leading
        let removalEdge: Edge = monthChangeDirection == .toNextMonth ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    /// 전환 애니메이션 방향(다음/이전 달) 판정용. 실제 달 식별은 currentMonthStart(아래)가 한다.
    private enum MonthChangeDirection {
        case toNextMonth
        case toPreviousMonth
    }

    /// 주(週) 그리드에 `.id(...)`로 붙여, "같은 달 안에서 날짜만 선택"할 때는 전환 애니메이션이
    /// 다시 돌지 않고 "실제로 달이 바뀔 때"만 돌도록 한다(currentDate 전체가 아니라 월 단위로 비교).
    private var currentMonthStart: Date {
        calendar.dateInterval(of: .month, for: currentDate)?.start ?? currentDate
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

/// WeekEventLayout의 init 파라미터라 유닛 테스트 타깃에서도 생성할 수 있도록 internal로 둔다.
struct CalendarWeek: Identifiable {
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
    // 단일 날짜 일정이 2줄로 확장될 때의 높이. 폰트 크기(11pt)는 그대로 두고 줄 수만 늘린다.
    // 11pt 시스템 폰트의 실제 줄 높이는 약 13.1pt라 eventHeight*2(26)로는 2번째 줄 아래가
    // 미세하게 잘릴 수 있어 1pt 여유를 둔다.
    private let twoLineEventHeight: CGFloat = 27
    private let eventSpacing: CGFloat = 1
    // 세로 공간이 허용하는 한 하루 최대 4개까지 보여준다(공간이 부족하면 배치 엔진이 자연히
    // 3개 이하로 줄이고 나머지를 +N으로 넘긴다 — WeekEventLayout의 placement 적합성 검사 참고).
    private let maximumVisibleEventsPerDay = 4

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
                            calendar: calendar
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

private struct CalendarEventBar: View {
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

            return first.occurrence.startDate < second.occurrence.startDate
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

#Preview {
    CalendarView()
        .modelContainer(for: Event.self, inMemory: true)
}
