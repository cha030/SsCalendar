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
    @State private var timeZoneRefreshGeneration = 0
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
    ) private var holidayCountryRawValue = HolidayCountry.defaultCountry.rawValue
    @State private var systemOccurrences: [CalendarDisplayOccurrence] = []
    @State private var systemCalendar = SystemCalendarService.shared

    let systemCalendarRefreshGeneration: Int

    init(systemCalendarRefreshGeneration: Int = 0) {
        self.systemCalendarRefreshGeneration = systemCalendarRefreshGeneration
    }

    private var calendar: Calendar {
        DeviceCalendar.current
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
                                holidayCountry.usesColoredWeekendsForDisplay && index == 0 ? .red :
                                holidayCountry.usesColoredWeekendsForDisplay && index == 6 ? .blue :
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
                timeZoneRefreshGeneration += 1
                WidgetReloadManager.reloadCalendar()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                timeZoneRefreshGeneration += 1
                WidgetReloadManager.reloadCalendar()
            }
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
        HolidayCountry(rawValue: holidayCountryRawValue) ?? HolidayCountry.defaultCountry
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
            let date = Self.deepLinkDateFormatter().date(from: dateString)
        else {
            return
        }

        currentDate = date
        selectedDate = date
        if url.host == "event" {
            guard
                let eventIDString = components?.queryItems?.first(where: { $0.name == "eventID" })?.value,
                let eventID = UUID(uuidString: eventIDString),
                components?.queryItems?
                    .first(where: { $0.name == "occurrenceStart" })?.value
                    .flatMap(Double.init) != nil,
                components?.queryItems?
                    .first(where: { $0.name == "originalOccurrenceStart" })?.value
                    .flatMap(Double.init) != nil,
                events.contains(where: { $0.id == eventID })
            else {
                // 삭제됐거나 더 이상 접근할 수 없는 일정은 다른 화면이나 일정을 임의로 열지 않는다.
                return
            }

            // 일정 식별 정보는 링크에서 검증만 하고, 편집 화면은 자동으로 열지 않는다.
            // 기존 day 딥링크와 같은 NavigationStack 경로로 해당 날짜의 일간 화면만 연다.
            newEventDate = nil
            schedulePath = [date]
            return
        }
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

    private static func deepLinkDateFormatter() -> DateFormatter {
        DeviceCalendar.dateFormatter(
            format: "yyyy-MM-dd",
            calendar: DeviceCalendar.current
        )
    }

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
        CalendarMonthGrid.monthStart(for: currentDate, calendar: calendar)
    }

    private var visibleWeeks: [CalendarWeek] {
        CalendarMonthGrid.visibleWeeks(for: currentDate, calendar: calendar)
    }

    private var visibleDates: [Date] {
        CalendarMonthGrid.visibleDates(for: currentDate, calendar: calendar)
    }
}

private struct SystemCalendarFetchKey: Equatable {
    let interval: DateInterval?
    let isEnabled: Bool
    let changeToken: Int
    let refreshGeneration: Int
}

#Preview {
    CalendarView()
        .modelContainer(for: Event.self, inMemory: true)
}
