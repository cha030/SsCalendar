import EventKit
import SwiftData
import SwiftUI

/// 좌우 스와이프로 넘어갈 때 어느 쪽에서 들어오고 나가는지. 전환 애니메이션 방향에만 쓴다.
private enum DayNavigationDirection {
    case toNextDay
    case toPreviousDay
}

struct DayScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.startDate, order: .forward) private var events: [Event]
    /// 외부 일정의 D-Day 설정(Step 5-2). 외부 캘린더 원본은 건드리지 않고, 이 로컬 데이터만 읽고 쓴다.
    @Query private var externalDDaySettings: [ExternalEventDDaySetting]
    /// 반복 일정의 개별 수정·삭제 예외(Step 5-2).
    @Query private var occurrenceExceptions: [EventOccurrenceException]
    @State private var isPresentingEventEditor = false
    @State private var selectedLocalEvent: SelectedLocalEvent?
    @State private var dayHolidays: [Holiday] = []
    @AppStorage(
        SystemCalendarService.isEnabledStorageKey,
        store: SystemCalendarService.settingsStore
    ) private var isSystemCalendarEnabled = false
    @AppStorage(
        HolidayCountry.storageKey,
        store: HolidayCountry.settingsStore
    ) private var holidayCountryRawValue = HolidayCountry.defaultCountry.rawValue
    @State private var systemOccurrences: [CalendarDisplayOccurrence] = []
    @State private var presentedSystemEvent: SystemEventPresentation?
    @State private var systemEventError: SystemCalendarAccessError?
    @State private var systemCalendar = SystemCalendarService.shared

    /// 화면에 실제로 표시 중인 날짜. 처음엔 `date`로 시작하지만, 좌우 스와이프로 바뀐다
    /// (화면을 닫았다 다시 열지 않고 날짜·일정 목록만 갱신하기 위해 전달받은 값을 그대로 쓰지 않는다).
    @State private var currentDate: Date
    @State private var navigationDirection: DayNavigationDirection = .toNextDay

    let systemCalendarRefreshGeneration: Int
    /// 스와이프로 다른 날짜를 보게 될 때마다 호출된다. 월간 달력(CalendarView)이 자신의
    /// 선택 날짜·표시 중인 달을 같이 갱신해 두면, 이 화면을 닫았을 때 바로 동기화돼 있다.
    private let onNavigateToDate: (Date) -> Void

    init(
        date: Date,
        systemCalendarRefreshGeneration: Int = 0,
        onNavigateToDate: @escaping (Date) -> Void = { _ in }
    ) {
        _currentDate = State(initialValue: date)
        self.systemCalendarRefreshGeneration = systemCalendarRefreshGeneration
        self.onNavigateToDate = onNavigateToDate
    }

    private var dateTitle: String {
        currentDate.formatted(
            Date.FormatStyle()
                .month(.defaultDigits)
                .day()
                .weekday(.wide)
                .locale(Locale.current)
        )
    }

    private var dayInterval: DateInterval? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: currentDate)

        guard let nextDayStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: dayStart
        ) else {
            return nil
        }

        return DateInterval(start: dayStart, end: nextDayStart)
    }

    /// 하루 앞/뒤로 이동한다. Calendar 기반 날짜 연산이라 월말·연말도 자연히 처리된다.
    private func navigate(by dayDelta: Int) {
        guard let newDate = Calendar.current.date(
            byAdding: .day,
            value: dayDelta,
            to: currentDate
        ) else {
            return
        }

        navigationDirection = dayDelta > 0 ? .toNextDay : .toPreviousDay
        withAnimation(.easeInOut(duration: 0.22)) {
            currentDate = newDate
        }
        onNavigateToDate(newDate)
    }

    /// 세로 스크롤과 헷갈리지 않도록, 끝난 뒤 가로 이동량이 세로 이동량보다 뚜렷이 크고
    /// 최소 거리를 넘었을 때만 스와이프로 인정한다. List의 스크롤 제스처를 막지 않도록
    /// `simultaneousGesture`로 붙여 세로 스크롤은 항상 그대로 동작한다.
    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                guard
                    abs(horizontal) > 60,
                    abs(horizontal) > abs(vertical) * 2
                else {
                    return
                }

                // 오른쪽으로 스와이프(이전 날짜)는 화면 왼쪽 가장자리에서 시작하는 iOS 기본
                // "뒤로 가기" 엣지 스와이프와 시작 지점이 겹친다. 이 영역에서 시작한 제스처는
                // 시스템 뒤로 가기에 양보하고 날짜는 바꾸지 않는다.
                let isEdgeSwipeBackZone = value.startLocation.x < 24
                guard horizontal < 0 || !isEdgeSwipeBackZone else {
                    return
                }

                navigate(by: horizontal < 0 ? 1 : -1)
            }
    }

    private var orderedOccurrences: [CalendarDisplayOccurrence] {
        guard let dayInterval else {
            return []
        }

        let localOccurrences = EventOccurrenceService.occurrences(
            for: events,
            intersecting: dayInterval,
            calendar: Calendar.current,
            exceptions: occurrenceExceptions
        )
        .map { CalendarDisplayOccurrence(local: $0) }

        return CalendarDisplayOccurrence.merged(
            local: localOccurrences,
            system: isSystemCalendarEnabled ? systemOccurrences : []
        )
    }

    private var holidayCountry: HolidayCountry {
        HolidayCountry(rawValue: holidayCountryRawValue) ?? HolidayCountry.defaultCountry
    }

    private var holidayTitle: String? {
        HolidayDisplayFormatter.title(
            for: dayHolidays.filter(\.isHoliday).map(\.name),
            on: currentDate
        )
    }

    private var holidayFetchKey: DayHolidayFetchKey {
        DayHolidayFetchKey(
            date: Calendar.current.startOfDay(for: currentDate),
            country: holidayCountry
        )
    }

    private var systemCalendarFetchKey: DaySystemCalendarFetchKey {
        DaySystemCalendarFetchKey(
            interval: dayInterval,
            isEnabled: isSystemCalendarEnabled,
            changeToken: systemCalendar.changeToken,
            refreshGeneration: systemCalendarRefreshGeneration
        )
    }

    private func loadDayHolidays(for key: DayHolidayFetchKey) async {
        let components = Calendar.current.dateComponents(
            [.year, .month],
            from: key.date
        )
        guard
            let year = components.year,
            let month = components.month
        else {
            dayHolidays = []
            return
        }

        do {
            let holidays = try await HolidayService.shared.holidays(
                for: HolidayMonth(year: year, month: month),
                country: key.country
            )
            guard !Task.isCancelled else { return }
            dayHolidays = holidays.filter {
                $0.isHoliday && Calendar.current.isDate($0.date, inSameDayAs: key.date)
            }
        } catch {
            dayHolidays = []
        }
    }

    private func loadSystemOccurrences(for key: DaySystemCalendarFetchKey) {
        guard key.isEnabled, let interval = key.interval else {
            systemOccurrences = []
            return
        }

        systemOccurrences = systemCalendar.occurrences(in: interval)
    }

    /// 이 발생분의 D-Day 미리보기 배지 문구. 켜져 있지 않거나 이미 지난 일정이면 nil(배지 숨김).
    /// 로컬은 Event.isDDayEnabled를, 외부 일정은 ExternalEventDDaySetting을 각각 확인한다.
    private func dDayText(for occurrence: CalendarDisplayOccurrence) -> String? {
        let isEnabled: Bool
        if let eventID = occurrence.localEventID {
            isEnabled = events.first { $0.id == eventID }?.isDDayEnabled ?? false
        } else if let reference = occurrence.systemEventReference {
            isEnabled = ExternalDDayStore.isEnabled(for: reference, in: externalDDaySettings)
        } else {
            isEnabled = false
        }
        guard isEnabled else { return nil }

        let days = DDayCalculator.daysRemaining(until: occurrence.startDate, calendar: Calendar.current)
        guard days >= 0 else { return nil }
        return DDayCalculator.displayText(forDaysRemaining: days)
    }

    /// 이 발생분에 이미 적용돼 있던 개별 수정·삭제 예외를 찾는다. 초 단위 오차를 허용해
    /// 비교한다(EventOccurrenceService가 같은 기준으로 만든 값이라 정상적으로는 오차가 없다).
    private func existingException(
        eventID: UUID,
        originalOccurrenceStartDate: Date
    ) -> EventOccurrenceException? {
        occurrenceExceptions.first {
            $0.eventID == eventID &&
            abs($0.originalOccurrenceStartDate.timeIntervalSince(originalOccurrenceStartDate)) < 1
        }
    }

    private func isExternalDDayEnabled(_ occurrence: CalendarDisplayOccurrence) -> Bool {
        guard let reference = occurrence.systemEventReference else { return false }
        return ExternalDDayStore.isEnabled(for: reference, in: externalDDaySettings)
    }

    /// 외부 일정의 D-Day를 켜거나 끈다. 외부 캘린더 원본(EKEvent)은 건드리지 않고, SsCalendar
    /// 로컬 설정(ExternalEventDDaySetting)만 upsert한다 — 같은 일정을 중복 생성하지 않는다.
    private func toggleExternalDDay(for occurrence: CalendarDisplayOccurrence) {
        guard let reference = occurrence.systemEventReference else { return }

        ExternalDDayStore.setEnabled(
            !isExternalDDayEnabled(occurrence),
            for: reference,
            existingSettings: externalDDaySettings,
            context: modelContext
        )

        do {
            try modelContext.save()
            WidgetReloadManager.reloadCalendar()
        } catch {
            modelContext.rollback()
        }
    }

    /// 탭한 발생분의 원본을 다시 조회해 Apple 일정 화면을 연다.
    /// 다른 기기에서 삭제되었거나 권한이 사라졌으면 안내하고, 남은 목록을 새로 고친다.
    private func openSystemEvent(_ occurrence: CalendarDisplayOccurrence) {
        guard let reference = occurrence.systemEventReference else { return }

        do {
            let event = try systemCalendar.event(for: reference)
            presentedSystemEvent = SystemEventPresentation(
                event: event,
                allowsEditing: systemCalendar.canModify(event)
            )
        } catch {
            systemEventError = error
            systemCalendar.reloadAfterSystemEventChange()
        }
    }

    /// 상세 화면이 열린 동안 캘린더가 바뀌면 원본이 아직 있는지 확인한다.
    /// 사용자가 상세 화면에서 직접 삭제한 경우에도 변경 알림이 먼저 올 수 있으므로,
    /// 잠시 기다려 delegate의 완료 처리(시트 닫힘)가 먼저 반영되게 한 뒤 판단한다.
    private func verifyPresentedSystemEvent() async {
        guard let presentation = presentedSystemEvent else { return }

        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            // 취소됐다면(바뀐 changeToken으로 다음 .task(id:)가 이미 새로 시작됐다는 뜻) 여기서
            // 끝낸다. 과거엔 try?로 취소 오류를 무시하고 그대로 진행해, 의도한 500ms보다 훨씬
            // 짧게 기다린 상태로 EKEvent.refresh()를 판단해 버리는 경쟁 상태가 있었다 — 자신이
            // 방금 삭제한 일정인데도 "일정을 열 수 없습니다" 알림이 잘못 뜰 수 있었다. 다음 호출이
            // 온전한 500ms를 기다린 뒤 다시 검증하므로 여기서는 그냥 반환하면 된다.
            return
        }

        guard
            presentedSystemEvent?.id == presentation.id,
            !presentation.event.refresh()
        else {
            return
        }

        presentedSystemEvent = nil
        systemEventError = .eventNotFound
    }

    private var isShowingSystemEventError: Binding<Bool> {
        Binding(
            get: { systemEventError != nil },
            set: { if !$0 { systemEventError = nil } }
        )
    }

    var body: some View {
        ZStack {
            List {
                if let holidayTitle {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red)
                            .frame(width: 4)

                        Text(holidayTitle.replacingOccurrences(of: "\n", with: " "))
                            .font(.body)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.vertical, 4)
                    .listRowSeparator(.hidden)
                }

                ForEach(orderedOccurrences) { occurrence in
                    if let eventID = occurrence.localEventID {
                        LocalEventRow(
                            occurrence: occurrence,
                            dDayText: dDayText(for: occurrence)
                        ) {
                            // 반복 일정은 모든 발생분이 같은 Event를 공유하므로(eventID 동일),
                            // 탭한 발생분의 실제 날짜와 원래 발생 슬롯을 함께 전달한다.
                            if let event = events.first(where: { $0.id == eventID }) {
                                selectedLocalEvent = SelectedLocalEvent(
                                    event: event,
                                    occurrenceStartDate: occurrence.startDate,
                                    occurrenceEndDate: occurrence.endDate,
                                    originalOccurrenceStartDate: occurrence.originalStartDate,
                                    existingException: existingException(
                                        eventID: event.id,
                                        originalOccurrenceStartDate: occurrence.originalStartDate
                                    )
                                )
                            }
                        }
                    } else {
                        ExternalEventRow(
                            occurrence: occurrence,
                            dDayText: dDayText(for: occurrence),
                            isAccessEnabled: SystemCalendarService.isExternalEventAccessEnabled,
                            isDDayEnabled: isExternalDDayEnabled(occurrence),
                            onOpen: {
                                openSystemEvent(occurrence)
                            },
                            onToggleDDay: {
                                toggleExternalDDay(for: occurrence)
                            }
                        )
                    }
                }
            }
            // 날짜가 바뀔 때마다 새 목록으로 취급해 전환 애니메이션이 자연스럽게 적용되게 한다.
            // 탭·상세 보기·편집·삭제는 List 내부 동작이라 이 변경과 무관하게 그대로 유지된다.
            .id(currentDate)
            .transition(
                .asymmetric(
                    insertion: .move(
                        edge: navigationDirection == .toNextDay ? .trailing : .leading
                    ).combined(with: .opacity),
                    removal: .move(
                        edge: navigationDirection == .toNextDay ? .leading : .trailing
                    ).combined(with: .opacity)
                )
            )

            if orderedOccurrences.isEmpty && holidayTitle == nil {
                Text("일정이 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .id(currentDate)
                    .transition(.opacity)
            }
        }
        // List 고유의 세로 스크롤 제스처를 막지 않도록 simultaneousGesture로 붙인다.
        // onEnded에서 가로/세로 이동량을 비교해 뚜렷한 가로 스와이프일 때만 날짜를 바꾼다.
        .simultaneousGesture(daySwipeGesture)
        .task(id: holidayFetchKey) {
            await loadDayHolidays(for: holidayFetchKey)
        }
        .task(id: systemCalendarFetchKey) {
            loadSystemOccurrences(for: systemCalendarFetchKey)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("뒤로가기")
            }

            ToolbarItem(placement: .principal) {
                Text(dateTitle)
                    .font(.headline)
                    // navigate(by:)가 currentDate 변경을 withAnimation으로 감싸므로, 그 값을 읽는
                    // 이 제목도 같은 애니메이션 트랜잭션을 물려받아 글자 폭이 바뀔 때(예: "금요일"→
                    // "토요일") 잠깐 왼쪽으로 밀렸다 돌아오는 것처럼 보였다. 날짜 변경은 List 쪽만
                    // 자연스럽게 전환되면 되므로, 제목은 애니메이션 없이 즉시 바뀌도록 명시적으로 끈다.
                    .animation(nil, value: currentDate)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingEventEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("일정 추가")
            }
        }
        .sheet(isPresented: $isPresentingEventEditor) {
            NavigationStack {
                EventEditorView(date: currentDate)
            }
        }
        .sheet(item: $selectedLocalEvent) { selection in
            NavigationStack {
                EventEditorView(
                    date: selection.occurrenceStartDate,
                    event: selection.event,
                    occurrenceEndDate: selection.occurrenceEndDate,
                    recurrenceSlotDate: selection.originalOccurrenceStartDate,
                    existingException: selection.existingException
                )
            }
            // selection.id는 일정 ID+발생 시각을 함께 묶으므로, 다른 발생분을 연달아 선택했을 때
            // SwiftUI가 직전 시트의 내용을 그대로 재사용해 첫 번째 진입에서 이전 발생분이 보이는
            // 문제(.sheet(item:)의 알려진 재사용 동작)를 막는다 — 값이 다르면 항상 새 화면으로 취급된다.
            .id(selection.id)
        }
        .sheet(item: $presentedSystemEvent, onDismiss: {
            // Done·삭제·초대 응답·스와이프 닫기 모두 이 경로로 끝난다.
            systemCalendar.reloadAfterSystemEventChange()
        }) { presentation in
            SystemEventDetailView(presentation: presentation) { _ in
                presentedSystemEvent = nil
            }
            .ignoresSafeArea()
        }
        .task(id: systemCalendar.changeToken) {
            await verifyPresentedSystemEvent()
        }
        .alert(
            "일정을 열 수 없습니다",
            isPresented: isShowingSystemEventError,
            presenting: systemEventError
        ) { _ in
            Button("확인", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}

private struct DayHolidayFetchKey: Equatable {
    let date: Date
    let country: HolidayCountry
}

private struct DaySystemCalendarFetchKey: Equatable {
    let interval: DateInterval?
    let isEnabled: Bool
    let changeToken: Int
    let refreshGeneration: Int
}

/// 자체 일정 편집 화면을 열 때 "어떤 Event"뿐 아니라 "그중 탭한 발생분(occurrence)이 언제인지"도
/// 함께 넘긴다. 반복 일정은 모든 발생분이 같은 Event를 공유하므로, 발생분 날짜를 같이 들고 있지
/// 않으면 항상 시리즈 원본 시작일(event.startDate)만 열리는 문제가 있었다.
private struct SelectedLocalEvent: Identifiable {
    let event: Event
    let occurrenceStartDate: Date
    let occurrenceEndDate: Date
    /// 반복 규칙이 원래 계산한 이 발생분괜차의 시작 시각(개별 수정 override 이전). 이미 한 번
    /// override된 발생분을 다시 열어도 항상 같은 예외 레코드를 찾을 수 있도록, 예외 식별 키는
    /// 항상 이 값을 쓴다(Step 5-2 개별 수정·삭제).
    let originalOccurrenceStartDate: Date
    /// 이 발생분에 이미 적용돼 있던 개별 수정 예외(있으면). 편집 화면을 열 때 override된 값을
    /// 그대로 보여주는 데 쓴다.
    let existingException: EventOccurrenceException?

    /// 같은 일정의 다른 발생분을 연달아 열어도 매번 새 시트로 인식되도록, 일정 ID와 원래 발생
    /// 시각을 함께 묶는다(일정 ID만 쓰면 같은 반복 일정의 다른 발생분을 구분할 수 없다).
    var id: String {
        "\(event.id.uuidString)-\(originalOccurrenceStartDate.timeIntervalSince1970)"
    }
}

#Preview {
    NavigationStack {
        DayScheduleView(date: Date())
    }
    // 이 화면이 ExternalEventDDaySetting도 @Query로 읽으므로(Step 5-2), 미리보기 컨테이너
    // 스키마에도 같이 등록해야 한다 — 빠지면 캔버스에서 스키마 조회 오류로 중단된다.
    .modelContainer(
        for: [Event.self, ExternalEventDDaySetting.self, EventOccurrenceException.self],
        inMemory: true
    )
}
