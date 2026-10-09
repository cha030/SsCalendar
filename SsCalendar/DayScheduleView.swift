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
    @Query(sort: \Event.startDate, order: .forward) private var events: [Event]
    @State private var isPresentingEventEditor = false
    @State private var selectedEvent: Event?
    @AppStorage(
        SystemCalendarService.isEnabledStorageKey,
        store: SystemCalendarService.settingsStore
    ) private var isSystemCalendarEnabled = false
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
            calendar: Calendar.current
        )
        .map { CalendarDisplayOccurrence(local: $0) }

        return CalendarDisplayOccurrence.merged(
            local: localOccurrences,
            system: isSystemCalendarEnabled ? systemOccurrences : []
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

    private func loadSystemOccurrences(for key: DaySystemCalendarFetchKey) {
        guard key.isEnabled, let interval = key.interval else {
            systemOccurrences = []
            return
        }

        systemOccurrences = systemCalendar.occurrences(in: interval)
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
        try? await Task.sleep(for: .milliseconds(500))

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
                ForEach(orderedOccurrences) { occurrence in
                    if let eventID = occurrence.localEventID {
                        Button {
                            selectedEvent = events.first { $0.id == eventID }
                        } label: {
                            EventRow(occurrence: occurrence)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // 시스템 캘린더 일정은 Apple 일정 화면에서 보기·수정·삭제한다.
                        Button {
                            openSystemEvent(occurrence)
                        } label: {
                            EventRow(occurrence: occurrence)
                        }
                        .buttonStyle(.plain)
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

            if orderedOccurrences.isEmpty {
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
        .sheet(item: $selectedEvent) { event in
            NavigationStack {
                EventEditorView(date: event.startDate, event: event)
            }
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

private struct DaySystemCalendarFetchKey: Equatable {
    let interval: DateInterval?
    let isEnabled: Bool
    let changeToken: Int
    let refreshGeneration: Int
}

private struct EventRow: View {
    let occurrence: CalendarDisplayOccurrence

    private var eventColor: Color {
        occurrence.color
    }

    private var timeDescription: String {
        if occurrence.isAllDay {
            return String(localized: "종일")
        }

        if Calendar.current.isDate(
            occurrence.startDate,
            inSameDayAs: occurrence.endDate
        ) {
            let timeStyle = Date.FormatStyle()
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
                .locale(Locale.current)
            let startTime = occurrence.startDate.formatted(timeStyle)
            let endTime = occurrence.endDate.formatted(timeStyle)
            return "\(startTime) – \(endTime)"
        }

        let dateTimeStyle = Date.FormatStyle()
            .month(.defaultDigits)
            .day(.defaultDigits)
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
            .locale(Locale.current)
        let startDateTime = occurrence.startDate.formatted(dateTimeStyle)
        let endDateTime = occurrence.endDate.formatted(dateTimeStyle)
        return "\(startDateTime) – \(endDateTime)"
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(eventColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(timeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if case .system(let calendarTitle, _) = occurrence.source {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                        Text(calendarTitle.isEmpty ? String(localized: "iPhone 캘린더") : calendarTitle)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        // plain 버튼은 그려진 글자만 탭되므로, Spacer를 포함한 행 전체를 탭 영역으로 지정한다.
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        DayScheduleView(date: Date())
    }
    .modelContainer(for: Event.self, inMemory: true)
}
