import SwiftData
import SwiftUI

enum EventColor: String, CaseIterable, Identifiable, Codable {
    case blue = "파란색"
    case red = "빨간색"
    case green = "초록색"
    case purple = "보라색"

    var id: Self { self }

    var color: Color {
        switch self {
        case .blue:
            return .blue
        case .red:
            return .red
        case .green:
            return .green
        case .purple:
            return .purple
        }
    }
}

private enum EventReminderOption: String, CaseIterable, Identifiable {
    case none = "없음"
    case atStart = "일정 시작 시간"
    case tenMinutesBefore = "10분 전"
    case oneHourBefore = "1시간 전"
    case oneDayBefore = "1일 전"
    case custom = "직접 설정"

    var id: Self { self }
}

private enum ReminderOffsetUnit: String, CaseIterable, Identifiable {
    case minute = "분 전"
    case hour = "시간 전"
    case day = "일 전"

    var id: Self { self }

    var seconds: TimeInterval {
        switch self {
        case .minute:
            return 60
        case .hour:
            return 3_600
        case .day:
            return 86_400
        }
    }
}

private struct EventReminderSetting {
    var option: EventReminderOption = .atStart
    var customValue = 30
    var customUnit: ReminderOffsetUnit = .minute

    var timeIntervalBeforeStart: TimeInterval? {
        switch option {
        case .none:
            return nil
        case .atStart:
            return 0
        case .tenMinutesBefore:
            return 10 * 60
        case .oneHourBefore:
            return 60 * 60
        case .oneDayBefore:
            return 24 * 60 * 60
        case .custom:
            return TimeInterval(customValue) * customUnit.seconds
        }
    }
}

private enum EventRepeatUnit: String, CaseIterable, Identifiable {
    case none = "반복 안 함"
    case day = "일"
    case week = "주"
    case month = "개월"
    case year = "년"

    var id: Self { self }
}

private struct EventRepeatSetting {
    var unit: EventRepeatUnit = .none
    var interval = 1

    var isRepeating: Bool {
        unit != .none
    }

    var summary: String {
        guard isRepeating else {
            return EventRepeatUnit.none.rawValue
        }

        return "\(interval)\(unit.rawValue)마다"
    }
}

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var isAllDay = false
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var eventColor: EventColor = .blue
    @State private var reminderSetting = EventReminderSetting()
    @State private var repeatSetting = EventRepeatSetting()
    @State private var notes = ""
    @State private var saveErrorMessage: String?
    @State private var isPresentingDeleteConfirmation = false
    @State private var isSaving = false

    private let event: Event?

    init(date: Date, event: Event? = nil) {
        self.event = event

        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: date)
        let defaultStartDate = calendar.date(
            byAdding: .hour,
            value: 7,
            to: selectedDay
        ) ?? selectedDay
        let defaultEndDate = calendar.date(
            byAdding: .hour,
            value: 8,
            to: selectedDay
        ) ?? defaultStartDate

        _title = State(initialValue: event?.title ?? "")
        _isAllDay = State(initialValue: event?.isAllDay ?? false)
        _startDate = State(initialValue: event?.startDate ?? defaultStartDate)
        _endDate = State(initialValue: event?.endDate ?? defaultEndDate)
        _eventColor = State(
            initialValue: event.flatMap { EventColor(rawValue: $0.color) } ?? .blue
        )
        _reminderSetting = State(
            initialValue: EventReminderSetting(
                option: event.flatMap {
                    EventReminderOption(rawValue: $0.alarmOption)
                } ?? .atStart,
                customValue: max(1, event?.alarmCustomValue ?? 30),
                customUnit: event.flatMap {
                    ReminderOffsetUnit(rawValue: $0.alarmCustomUnit)
                } ?? .minute
            )
        )
        _repeatSetting = State(
            initialValue: EventRepeatSetting(
                unit: event.flatMap {
                    EventRepeatUnit(rawValue: $0.repeatUnit)
                } ?? .none,
                interval: max(1, event?.repeatInterval ?? 1)
            )
        )
        _notes = State(initialValue: event?.memo ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("제목", text: $title)
            }

            Section {
                Toggle("하루 종일", isOn: $isAllDay)

                DatePicker(
                    "시작",
                    selection: $startDate,
                    displayedComponents: isAllDay
                        ? .date
                        : [.date, .hourAndMinute]
                )
                .environment(
                    \.locale,
                    Locale(identifier: "ko_KR")
                )

                DatePicker(
                    "종료",
                    selection: $endDate,
                    displayedComponents: isAllDay
                        ? .date
                        : [.date, .hourAndMinute]
                )
                .environment(
                    \.locale,
                    Locale(identifier: "ko_KR")
                )
            }

            Section {
                HStack {
                    Text("색상")

                    Spacer()

                    HStack(spacing: 14) {
                        ForEach(EventColor.allCases) { colorOption in
                            Button {
                                eventColor = colorOption
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(colorOption.color)
                                        .frame(width: 24, height: 24)

                                    if eventColor == colorOption {
                                        Circle()
                                            .stroke(.primary, lineWidth: 2)
                                            .frame(width: 30, height: 30)

                                        Image(systemName: "checkmark")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(colorOption.rawValue)
                            .accessibilityValue(
                                eventColor == colorOption ? "선택됨" : "선택 안 됨"
                            )
                        }
                    }
                }
            }

            Section {
                Picker("알림", selection: $reminderSetting.option) {
                    ForEach(EventReminderOption.allCases) { option in
                        Text(option.rawValue)
                            .tag(option)
                    }
                }

                if reminderSetting.option == .custom {
                    LabeledContent("알림 시점") {
                        HStack {
                            TextField(
                                "값",
                                value: customReminderValue,
                                format: .number
                            )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)

                            Picker("", selection: $reminderSetting.customUnit) {
                                ForEach(ReminderOffsetUnit.allCases) { unit in
                                    Text(unit.rawValue)
                                        .tag(unit)
                                }
                            }
                            .labelsHidden()

                            Stepper(
                                "",
                                value: customReminderValue,
                                in: 1...999
                            )
                            .labelsHidden()
                        }
                    }
                }
            }

            Section {
                Picker("반복", selection: $repeatSetting.unit) {
                    ForEach(EventRepeatUnit.allCases) { unit in
                        Text(unit.rawValue)
                            .tag(unit)
                    }
                }

                if repeatSetting.isRepeating {
                    LabeledContent("반복 간격") {
                        HStack {
                            TextField(
                                "간격",
                                value: repeatInterval,
                                format: .number
                            )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)

                            Stepper(
                                "",
                                value: repeatInterval,
                                in: 1...999
                            )
                            .labelsHidden()
                        }
                    }

                    Text(repeatSetting.summary)
                        .foregroundStyle(.secondary)
                }
            }

            Section("메모") {
                TextEditor(text: $notes)
                    .frame(minHeight: 120)
            }

            if event != nil {
                Section {
                    Button("일정 삭제", role: .destructive) {
                        isPresentingDeleteConfirmation = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(event == nil ? "새 일정" : "일정 편집")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("취소") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("저장") {
                    Task {
                        await saveEvent()
                    }
                }
                .disabled(isSaving)
            }
        }
        .alert(
            "일정을 저장할 수 없습니다",
            isPresented: saveErrorIsPresented
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                Task {
                    await deleteEvent()
                }
            }

            Button("취소", role: .cancel) {}
        }
    }

    private var deleteConfirmationTitle: String {
        if let event, event.repeatUnit != EventRepeatUnit.none.rawValue {
            return "반복되는 모든 일정을 삭제하시겠습니까?"
        }

        return "이 일정을 삭제하시겠습니까?"
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private var customReminderValue: Binding<Int> {
        Binding(
            get: { reminderSetting.customValue },
            set: { reminderSetting.customValue = max(1, $0) }
        )
    }

    private var repeatInterval: Binding<Int> {
        Binding(
            get: { repeatSetting.interval },
            set: { repeatSetting.interval = max(1, $0) }
        )
    }

    private func saveEvent() async {
        guard endDate >= startDate else {
            saveErrorMessage = "종료 시간은 시작 시간보다 빠를 수 없습니다."
            return
        }

        isSaving = true
        let savedEvent: Event

        if let event {
            update(event)
            savedEvent = event
        } else {
            let newEvent = Event(
                title: title,
                isAllDay: isAllDay,
                startDate: startDate,
                endDate: endDate,
                color: eventColor.rawValue,
                alarmOption: reminderSetting.option.rawValue,
                alarmTimeIntervalBeforeStart: reminderSetting.timeIntervalBeforeStart,
                alarmCustomValue: reminderSetting.customValue,
                alarmCustomUnit: reminderSetting.customUnit.rawValue,
                repeatUnit: repeatSetting.unit.rawValue,
                repeatInterval: repeatSetting.interval,
                memo: notes
            )
            modelContext.insert(newEvent)
            savedEvent = newEvent
        }

        do {
            try modelContext.save()
            await NotificationManager.shared.rescheduleNotifications(
                for: savedEvent
            )
            isSaving = false
            dismiss()
        } catch {
            modelContext.rollback()
            isSaving = false
            saveErrorMessage = "저장 중 오류가 발생했습니다. 다시 시도해 주세요."
        }
    }

    private func update(_ event: Event) {
        event.title = title
        event.isAllDay = isAllDay
        event.startDate = startDate
        event.endDate = endDate
        event.color = eventColor.rawValue
        event.alarmOption = reminderSetting.option.rawValue
        event.alarmTimeIntervalBeforeStart = reminderSetting.timeIntervalBeforeStart
        event.alarmCustomValue = reminderSetting.customValue
        event.alarmCustomUnit = reminderSetting.customUnit.rawValue
        event.repeatUnit = repeatSetting.unit.rawValue
        event.repeatInterval = repeatSetting.interval
        event.memo = notes
    }

    private func deleteEvent() async {
        guard let event else {
            return
        }

        let eventID = event.id
        modelContext.delete(event)

        do {
            try modelContext.save()
            await NotificationManager.shared.cancelNotifications(
                for: eventID
            )
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = "삭제 중 오류가 발생했습니다. 다시 시도해 주세요."
        }
    }
}

#Preview {
    NavigationStack {
        EventEditorView(date: Date())
    }
    .modelContainer(for: Event.self, inMemory: true)
}
