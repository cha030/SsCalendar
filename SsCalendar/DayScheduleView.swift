import EventKit
import SwiftData
import SwiftUI

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

    let date: Date
    let systemCalendarRefreshGeneration: Int

    init(date: Date, systemCalendarRefreshGeneration: Int = 0) {
        self.date = date
        self.systemCalendarRefreshGeneration = systemCalendarRefreshGeneration
    }

    private var dateTitle: String {
        date.formatted(
            Date.FormatStyle()
                .month(.defaultDigits)
                .day()
                .weekday(.wide)
                .locale(Locale.current)
        )
    }

    private var dayInterval: DateInterval? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        guard let nextDayStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: dayStart
        ) else {
            return nil
        }

        return DateInterval(start: dayStart, end: nextDayStart)
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

            if orderedOccurrences.isEmpty {
                Text("일정이 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
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
                EventEditorView(date: date)
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
