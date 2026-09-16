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

    @State private var title = ""
    @State private var isAllDay = false
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var eventColor: EventColor = .blue
    @State private var reminderSetting = EventReminderSetting()
    @State private var repeatSetting = EventRepeatSetting()
    @State private var notes = ""

    init(date: Date) {
        _startDate = State(initialValue: date)
        _endDate = State(
            initialValue: Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: date
            ) ?? date
        )
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

                DatePicker(
                    "종료",
                    selection: $endDate,
                    displayedComponents: isAllDay
                        ? .date
                        : [.date, .hourAndMinute]
                )
            }

            Section {
                NavigationLink {
                    List {
                        ForEach(EventColor.allCases) { colorOption in
                            Button {
                                eventColor = colorOption
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(colorOption.color)
                                        .frame(width: 14, height: 14)

                                    Text(colorOption.rawValue)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if eventColor == colorOption {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("색상")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack {
                        Text("색상")

                        Spacer()

                        Circle()
                            .fill(eventColor.color)
                            .frame(width: 14, height: 14)

                        Text(eventColor.rawValue)
                            .foregroundStyle(.secondary)
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
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("새 일정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("취소") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("저장") {
                    // 일정 저장 기능은 추후 연결합니다.
                }
            }
        }
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
}

#Preview {
    NavigationStack {
        EventEditorView(date: Date())
    }
}
