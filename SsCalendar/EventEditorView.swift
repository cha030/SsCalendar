import SwiftData
import SwiftUI
import UIKit

enum EventColor: String, CaseIterable, Identifiable, Codable {
    case blue = "파란색"
    case red = "빨간색"
    case green = "초록색"
    case purple = "보라색"

    var id: Self { self }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .blue: "파란색"
        case .red: "빨간색"
        case .green: "초록색"
        case .purple: "보라색"
        }
    }

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

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .none: "없음"
        case .atStart: "일정 시작 시간"
        case .tenMinutesBefore: "10분 전"
        case .oneHourBefore: "1시간 전"
        case .oneDayBefore: "1일 전"
        case .custom: "직접 설정"
        }
    }
}

private enum ReminderOffsetUnit: String, CaseIterable, Identifiable {
    case minute = "분 전"
    case hour = "시간 전"
    case day = "일 전"

    var id: Self { self }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .minute: "분 전"
        case .hour: "시간 전"
        case .day: "일 전"
        }
    }

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

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .none: "반복 안 함"
        case .day: "일"
        case .week: "주"
        case .month: "개월"
        case .year: "년"
        }
    }
}

/// 반복 종료 방식(Step 5-2 반복 종료일 기능). 외부 EventKit 반복 규칙은 건드리지 않는다 —
/// SsCalendar 자체 일정에만 적용한다.
private enum EventRepeatEndOption: String, CaseIterable, Identifiable {
    case never = "종료 안 함"
    case onDate = "날짜 지정"

    var id: Self { self }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .never: "종료 안 함"
        case .onDate: "날짜 지정"
        }
    }
}

/// 반복 일정의 수정 범위(Step 5-2 개별 수정·삭제). 반복 일정을 편집할 때만 의미가 있다 — 새
/// 일정이거나 반복하지 않는 일정에는 쓰이지 않는다. 기본값은 "이 일정만"으로 둬 특정 발생분을
/// 열었을 때 실수로 시리즈 전체를 바꾸는 사고를 줄인다.
private enum OccurrenceEditScope: String, CaseIterable, Identifiable {
    case singleOccurrence = "이 일정만"
    case wholeSeries = "전체 반복 일정"

    var id: Self { self }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .singleOccurrence: "이 일정만"
        case .wholeSeries: "전체 반복 일정"
        }
    }
}

/// 전체 반복 일정 저장 시 기존 개별 수정 예외에 새 시리즈 값을 적용하는 방법.
private enum SeriesExceptionUpdateChoice: CaseIterable, Identifiable {
    case preserveIndividualChanges
    case applyChangedSeriesValues

    var id: Self { self }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .preserveIndividualChanges: "기존 개별 수정 유지"
        case .applyChangedSeriesValues: "개별 수정에도 전체 변경 적용"
        }
    }

    var localizedDescription: LocalizedStringResource {
        switch self {
        case .preserveIndividualChanges:
            "개별 수정한 값은 유지하고, 수정하지 않은 값만 새로운 전체 일정에 맞춥니다."
        case .applyChangedSeriesValues:
            "이번에 전체 일정에서 변경한 값만 개별 수정 일정에도 적용합니다."
        }
    }

    var updatePolicy: RecurringSeriesExceptionUpdatePolicy {
        switch self {
        case .preserveIndividualChanges: .preserveIndividualChanges
        case .applyChangedSeriesValues: .applyChangedSeriesValues
        }
    }
}

private struct EventRepeatSetting {
    var unit: EventRepeatUnit = .none
    var interval = 1

    var isRepeating: Bool {
        unit != .none
    }

    var summary: LocalizedStringResource {
        switch unit {
        case .none:
            return "반복 안 함"
        case .day:
            return "\(interval)일마다"
        case .week:
            return "\(interval)주마다"
        case .month:
            return "\(interval)개월마다"
        case .year:
            return "\(interval)년마다"
        }
    }

    /// 시스템 캘린더(EventKit) 저장용 반복 규칙. 반복 안 함이면 nil.
    var systemRepeatRule: (frequency: SystemEventDraft.RepeatFrequency, interval: Int)? {
        let frequency: SystemEventDraft.RepeatFrequency
        switch unit {
        case .none:
            return nil
        case .day:
            frequency = .daily
        case .week:
            frequency = .weekly
        case .month:
            frequency = .monthly
        case .year:
            frequency = .yearly
        }
        return (frequency, max(1, interval))
    }
}

/// UIKit이 소유한 marked text를 SwiftUI 상태 갱신이 조합 도중 되써서 깨뜨리지 않도록 하는 제목 입력기.
/// 입력값은 매번 Binding에 반영하되, 조합 중에는 외부 값을 UITextField로 다시 주입하지 않는다.
private struct CompositionSafeTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.text = $text
        textField.placeholder = placeholder

        // markedTextRange가 있는 동안 text를 대입하면 한국어 조합 세션과 선택 영역이 초기화될 수 있다.
        guard textField.markedTextRange == nil, textField.text != text else { return }
        textField.text = text
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func textDidChange(_ textField: UITextField) {
            // 한글 등 조합형 입력기가 조합 중(marked text)인 동안에는 그 중간값을 SwiftUI
            // 상태로 내보내지 않는다. 중간값을 Binding에 흘려보내면 SwiftUI body가 재평가되고
            // Form(List) 레이아웃이 다시 계산되는데, 바로 그 과정이 UITextField의 marked text
            // 조합 세션을 끊어 "ㄱㅗ기"처럼 자모가 분리되는 원인이 된다 — updateUIView 쪽만
            // 막아서는(SwiftUI→UIKit 역주입 방지) 부족했고, 이 반대 방향(UIKit→SwiftUI)도
            // 똑같이 막아야 한다. 조합이 끝나 확정된 텍스트만 반영한다.
            guard textField.markedTextRange == nil else { return }
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            // 포커스를 잃으면 iOS가 조합을 자동 확정하므로 보통 이 시점엔 marked text가 없다.
            // 혹시 모를 불일치에 대비해 최종값을 한 번 더 동기화하는 안전장치다.
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

/// 제목과 같은 동기화 원칙을 사용하는 여러 줄 메모 입력기.
private struct CompositionSafeTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.delegate = context.coordinator
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text

        guard textView.markedTextRange == nil, textView.text != text else { return }
        textView.text = text
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            // 제목 입력기와 동일한 이유로, 조합 중간값은 SwiftUI 상태로 내보내지 않는다.
            guard textView.markedTextRange == nil else { return }
            text.wrappedValue = textView.text
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
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
    /// 반복 종료 방식(Step 5-2). 기본값 "종료 안 함" — 기존 반복 일정은 전부 이 상태를 유지한다.
    @State private var repeatEndOption: EventRepeatEndOption = .never
    @State private var repeatEndDate: Date
    @State private var notes = ""
    /// D-Day(남은 일수) 표시 여부(Step 5-2). 기본값 OFF. startDate를 기준으로 계산하므로
    /// 시작 날짜가 바뀌면 미리보기도 같이 바뀐다(아래 dDayPreviewText).
    @State private var isDDayEnabled = false
    @State private var saveErrorMessage: String?
    @State private var isPresentingDeleteConfirmation = false
    @State private var isSaving = false
    /// 새 일정의 저장 위치. 기존 일정 편집에서는 항상 .local이며 변경할 수 없다.
    @State private var saveDestination: EventSaveDestination
    /// 반복 일정 수정 범위(Step 5-2). 반복 일정이 아니거나 새 일정이면 의미가 없다(항상
    /// wholeSeries처럼 동작 — 시리즈 자체를 만들거나 통째로 다루기 때문).
    @State private var editScope: OccurrenceEditScope = .singleOccurrence
    @State private var isPresentingSeriesExceptionChoice = false
    /// 데이터 보존이 기본이므로 선택창을 열 때마다 A를 기본 선택으로 사용한다.
    @State private var seriesExceptionChoice: SeriesExceptionUpdateChoice = .preserveIndividualChanges

    private let event: Event?
    private let systemCalendar = SystemCalendarService.shared
    /// 편집 중 EventKit 변경 알림이 와도 제목·메모 입력 뷰가 다시 구성되지 않도록, 편집기를 열 때
    /// 쓸 수 있던 캘린더 목록을 한 번만 읽는다. 저장 직전 유효성 검사는 서비스가 다시 수행한다.
    private let writableCalendarGroups: [SystemWritableCalendarSourceGroup]
    /// 저장된 기본 저장 위치를 쓸 수 없어 로컬로 선택했을 때의 안내 문구. 편집기를 연 시점에 한 번 정한다.
    private let defaultDestinationNotice: String?
    /// 편집기를 열 때 실제로 보여준 발생분의 시작·종료 시각(원본 그대로, 사용자가 편집하기 전 값).
    /// 반복 일정은 모든 발생분이 같은 Event를 공유해 "지금 보여준 게 시리즈 원본인지, 이후
    /// 회차인지" 구분이 필요하다 — update(_:)에서 이 값과 현재 입력값의 차이(delta)만큼만
    /// 시리즈 원본 시작·종료일을 옮긴다(반복이 아니거나 원본 회차를 열었으면 delta가 0이라
    /// 기존과 동일하게 동작한다).
    private let originalOccurrenceStartDate: Date
    private let originalOccurrenceEndDate: Date
    /// 반복 규칙이 원래 계산한 이 발생분의 시작 시각(개별 수정 override 이전). 예외 레코드를
    /// 찾고 만드는 키로 쓴다 — 이미 override된 발생분을 다시 열어도 항상 같은 값이라, 같은
    /// 예외를 중복 생성하지 않고 갱신할 수 있다(Step 5-2 개별 수정·삭제).
    private let exceptionKeyDate: Date
    /// 이 발생분에 이미 적용돼 있던 개별 수정 예외(있으면). "이 일정만 수정"을 다시 저장할 때
    /// 중복 생성하지 않고 이 레코드를 그대로 갱신한다.
    private let existingException: EventOccurrenceException?

    /// - Parameters:
    ///   - date: 새 일정이면 기본 시작 시각 계산에, 기존 일정 수정이면 탭한 발생분의 실제
    ///     시작 시각으로 쓰인다(반복 일정의 특정 회차를 열었을 수 있어 event.startDate를
    ///     그대로 쓰지 않는다).
    ///   - occurrenceEndDate: 기존 일정 수정일 때 탭한 발생분의 실제 종료 시각. 생략하면 date와
    ///     같은 값으로 취급한다(비정상적인 빈 구간 방지).
    ///   - recurrenceSlotDate: 반복 규칙이 원래 계산한 이 발생분의 시작 시각(개별 수정 예외 식별
    ///     키). 생략하면 date와 같은 값으로 취급한다(비반복 일정이거나 처음 수정하는 경우).
    ///   - existingException: 이 발생분에 이미 적용돼 있던 개별 수정 예외(있으면). 제목·색상·알림·
    ///     메모의 초기값을 이 예외에서 가져와, 이미 한 번 수정한 발생분을 다시 열어도 override된
    ///     값이 그대로 보이게 한다(시간은 occurrenceEndDate/date가 이미 override를 반영해 넘어온다).
    ///
    /// 반복 일정 수정 범위(이 일정만/전체 반복 일정)는 항상 "이 일정만"으로 열리며, 화면 안의
    /// 세그먼트 Picker로 바꿀 수 있다 — 특정 발생분을 열었을 때 실수로 시리즈 전체를 바꾸는
    /// 사고를 줄이기 위한 안전한 기본값이다(OccurrenceEditScope는 이 파일 전용 타입이라
    /// 초기화 파라미터로 외부에 노출하지 않는다).
    init(
        date: Date,
        event: Event? = nil,
        occurrenceEndDate: Date? = nil,
        recurrenceSlotDate: Date? = nil,
        existingException: EventOccurrenceException? = nil
    ) {
        self.event = event
        self.existingException = existingException

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

        let occurrenceStartDate = event != nil ? date : defaultStartDate
        let occurrenceEndDate = event != nil ? (occurrenceEndDate ?? date) : defaultEndDate
        originalOccurrenceStartDate = occurrenceStartDate
        originalOccurrenceEndDate = occurrenceEndDate
        exceptionKeyDate = recurrenceSlotDate ?? occurrenceStartDate
        _editScope = State(initialValue: .singleOccurrence)

        _title = State(initialValue: existingException?.overrideTitle ?? event?.title ?? "")
        _isAllDay = State(initialValue: existingException?.overrideIsAllDay ?? event?.isAllDay ?? false)
        _startDate = State(initialValue: occurrenceStartDate)
        _endDate = State(initialValue: occurrenceEndDate)
        _eventColor = State(
            initialValue: EventColor(rawValue: existingException?.overrideColor ?? event?.color ?? "") ?? .blue
        )
        _reminderSetting = State(
            initialValue: EventReminderSetting(
                option: EventReminderOption(
                    rawValue: existingException?.overrideAlarmOption ?? event?.alarmOption ?? ""
                ) ?? .atStart,
                customValue: max(1, existingException?.overrideAlarmCustomValue ?? event?.alarmCustomValue ?? 30),
                customUnit: ReminderOffsetUnit(
                    rawValue: existingException?.overrideAlarmCustomUnit ?? event?.alarmCustomUnit ?? ""
                ) ?? .minute
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
        _repeatEndOption = State(
            initialValue: event?.repeatEndDate != nil ? .onDate : .never
        )
        // "종료 안 함"이어도 사용자가 "날짜 지정"으로 바꿀 때 보여줄 기본값을 미리 마련해 둔다
        // (시작일 + 1년). 기존에 저장된 종료일이 있으면 그 값을 그대로 쓴다.
        _repeatEndDate = State(
            initialValue: event?.repeatEndDate
                ?? calendar.date(byAdding: .year, value: 1, to: occurrenceStartDate)
                ?? occurrenceStartDate
        )
        _notes = State(initialValue: existingException?.overrideMemo ?? event?.memo ?? "")
        _isDDayEnabled = State(initialValue: event?.isDDayEnabled ?? false)

        let systemCalendar = SystemCalendarService.shared
        writableCalendarGroups = event == nil
            ? systemCalendar.writableCalendarGroups()
            : []
        _saveDestination = State(
            initialValue: event == nil && SystemCalendarService.isExternalEventAccessEnabled
                ? systemCalendar.effectiveDefaultSaveDestination
                : .local
        )
        // 연동 OFF는 사용자가 직접 끈 상태이므로 안내하지 않고, 기존 로컬 생성 방식만 보여준다.
        // 저장된 기본값은 지우지 않으므로 계정·권한이 돌아오면 다시 기본 저장 위치로 쓰인다.
        if event == nil,
           let issue = systemCalendar.defaultSaveDestinationIssue,
           issue != .integrationDisabled {
            defaultDestinationNotice = String(localized: "기본 저장 위치로 설정한 캘린더를 사용할 수 없어 SsCalendar에 저장하도록 선택했습니다. \(issue.message)")
        } else {
            defaultDestinationNotice = nil
        }
    }

    private var isSavingToSystemCalendar: Bool {
        if case .systemCalendar = saveDestination { return true }
        return false
    }

    var body: some View {
        Form {
            Section {
                CompositionSafeTextField(
                    text: $title,
                    placeholder: String(localized: "제목")
                )
            }

            // 반복 일정 수정 범위 선택(Step 5-2 개별 수정·삭제). 새 일정이거나 반복하지 않는
            // 일정에는 "시리즈" 개념이 없어 보여주지 않는다.
            if isExistingRepeatingSeries {
                Section {
                    Picker("수정 범위", selection: $editScope) {
                        ForEach(OccurrenceEditScope.allCases) { scope in
                            Text(scope.localizedTitle).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(
                        editScope == .singleOccurrence
                            ? "이 발생분만 수정합니다. 반복 설정과 D-Day는 \"전체 반복 일정\"에서만 바꿀 수 있습니다."
                            : "반복되는 모든 발생분에 적용됩니다."
                    )
                }
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
                    Locale.current
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
                    Locale.current
                )
            }

            saveDestinationSection

            // 시스템 캘린더 일정은 원본 캘린더 색상을 사용하므로 색상 선택을 숨긴다.
            if !isSavingToSystemCalendar {
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
                                .accessibilityLabel(Text(colorOption.localizedTitle))
                                .accessibilityValue(
                                    eventColor == colorOption ? "선택됨" : "선택 안 됨"
                                )
                            }
                        }
                    }
                }
            }

            Section {
                Picker("알림", selection: $reminderSetting.option) {
                    ForEach(EventReminderOption.allCases) { option in
                        Text(option.localizedTitle)
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
                                    Text(unit.localizedTitle)
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
                if isEditingSingleOccurrenceOfRepeatingSeries {
                    // 이 발생분만 수정하는 중에는 반복 설정 자체를 바꿀 수 없다(시리즈 전체에
                    // 적용되는 값이기 때문) — 현재 값을 읽기 전용으로만 보여준다.
                    LabeledContent("반복") {
                        Text(repeatSetting.summary)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("반복", selection: $repeatSetting.unit) {
                        ForEach(EventRepeatUnit.allCases) { unit in
                            Text(unit.localizedTitle)
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

                        // 반복 종료(Step 5-2). SsCalendar 자체 일정에만 적용하며, 외부 EventKit
                        // 반복 규칙은 건드리지 않는다. 기본값 "종료 안 함"(기존 무기한 반복과 동일).
                        Picker("반복 종료", selection: $repeatEndOption) {
                            ForEach(EventRepeatEndOption.allCases) { option in
                                Text(option.localizedTitle)
                                    .tag(option)
                            }
                        }

                        if repeatEndOption == .onDate {
                            // 종료일이 시작일보다 앞설 수 없도록 선택 범위 자체를 제한한다(UI 단계
                            // 검증). saveEvent()에서도 한 번 더 확인한다(날짜 선택 순서와 무관하게).
                            DatePicker(
                                "종료 날짜",
                                selection: $repeatEndDate,
                                in: startDate...,
                                displayedComponents: .date
                            )
                            .environment(\.locale, Locale.current)
                        }
                    }
                }
            }

            Section("메모") {
                CompositionSafeTextEditor(text: $notes)
                    .frame(minHeight: 120)
            }

            // 시스템 캘린더에 직접 저장하는 새 일정은 아직 SsCalendar 로컬 Event가 없어 D-Day
            // 설정을 저장할 곳이 없다. 저장 후 외부 일정 상세에서 별도로 켤 수 있다(Step 5-2 2-2).
            // D-Day는 시리즈 전체에 적용되는 설정이라, "이 일정만" 수정 중에는 바꿀 수 없다.
            if !isSavingToSystemCalendar && !isEditingSingleOccurrenceOfRepeatingSeries {
                Section {
                    Toggle("D-Day 표시", isOn: $isDDayEnabled)

                    if isDDayEnabled {
                        LabeledContent("미리보기") {
                            Text(dDayPreviewText)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(dDayFooterText)
                }
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
        // 기존 스크롤 제스처 동작은 유지한다. 한국어 조합 보호는 위 입력기들이 marked text를
        // 보유한 동안 외부 상태를 재주입하지 않는 방식으로 처리한다.
        .scrollDismissesKeyboard(.immediately)
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
            if isExistingRepeatingSeries {
                Button("이 일정만 삭제", role: .destructive) {
                    Task {
                        await deleteSingleOccurrence()
                    }
                }

                Button("전체 반복 일정 삭제", role: .destructive) {
                    Task {
                        await deleteEvent()
                    }
                }
            } else {
                Button("삭제", role: .destructive) {
                    Task {
                        await deleteEvent()
                    }
                }
            }

            Button("취소", role: .cancel) {}
        }
        .sheet(isPresented: $isPresentingSeriesExceptionChoice) {
            NavigationStack {
                Form {
                    Section {
                        Picker("개별 수정 처리", selection: $seriesExceptionChoice) {
                            ForEach(SeriesExceptionUpdateChoice.allCases) { choice in
                                Text(choice.localizedTitle).tag(choice)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("기존 개별 수정 처리")
                    } footer: {
                        Text(seriesExceptionChoice.localizedDescription)
                    }
                }
                .navigationTitle("전체 반복 일정 수정")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") {
                            isPresentingSeriesExceptionChoice = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            isPresentingSeriesExceptionChoice = false
                            Task {
                                await saveEvent(exceptionPolicy: seriesExceptionChoice.updatePolicy)
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var saveDestinationSection: some View {
        let groups = writableCalendarGroups

        if SystemCalendarService.isExternalEventAccessEnabled, !groups.isEmpty {
            Section {
                Picker("저장 위치", selection: $saveDestination) {
                    Label {
                        Text("SsCalendar")
                    } icon: {
                        Image(systemName: "iphone")
                            .foregroundStyle(.secondary)
                    }
                    .tag(EventSaveDestination.local)

                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.calendars) { calendar in
                                Label {
                                    Text(calendar.title)
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(calendar.color)
                                }
                                .tag(
                                    EventSaveDestination.systemCalendar(
                                        calendarIdentifier: calendar.id
                                    )
                                )
                            }
                        }
                    }
                }
                .pickerStyle(.navigationLink)
            } footer: {
                if let defaultDestinationNotice {
                    Text(defaultDestinationNotice)
                } else if isSavingToSystemCalendar {
                    Text("iPhone 캘린더에 저장되며, 캘린더 색상이 적용됩니다.")
                }
            }
        } else if let defaultDestinationNotice {
            Section {
                Text(defaultDestinationNotice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 시스템 캘린더 저장용 입력값. 알림은 EKAlarm, 반복은 EKRecurrenceRule로 변환된다.
    private var systemEventDraft: SystemEventDraft {
        SystemEventDraft(
            title: title,
            isAllDay: isAllDay,
            startDate: startDate,
            endDate: endDate,
            notes: notes,
            alarmOffsetBeforeStart: reminderSetting.timeIntervalBeforeStart,
            repeatRule: repeatSetting.systemRepeatRule
        )
    }

    private var deleteConfirmationTitle: String {
        if let event, event.repeatUnit != EventRepeatUnit.none.rawValue {
            return String(localized: "반복되는 모든 일정을 삭제하시겠습니까?")
        }

        return String(localized: "이 일정을 삭제하시겠습니까?")
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

    /// "종료 안 함"이면 nil, "날짜 지정"이면 선택한 날짜. 반복이 아니면(반복 설정 자체가
    /// 꺼져 있으면) 항상 nil — 반복하지 않는 일정에는 종료 설정을 적용하지 않는다.
    private var effectiveRepeatEndDate: Date? {
        guard repeatSetting.isRepeating, repeatEndOption == .onDate else { return nil }
        return repeatEndDate
    }

    /// 지금 편집 중인 발생분(startDate)을 그대로 기준으로 D-Day 미리보기를 계산한다(Step 5-2
    /// 실기기 수정: 반복 일정에서 다른 발생분을 열어도 항상 "지금 보고 있는 그 발생분"의 D-Day를
    /// 보여줘야 하며, 시리즈의 "오늘 이후 다음 발생일"을 임의로 대신 보여주지 않는다). @State인
    /// startDate를 직접 읽으므로 날짜를 바꾸면 body가 다시 그려질 때 즉시 재계산된다.
    private var dDayPreviewText: String {
        let days = DDayCalculator.daysRemaining(until: startDate, calendar: Calendar.current)
        guard days >= 0 else {
            return String(localized: "지난 일정")
        }
        return DDayCalculator.displayText(forDaysRemaining: days)
    }

    /// D-Day 섹션 footer 설명. 반복 여부에 따라 기준이 달라지므로 그에 맞춰 문구를 바꾼다.
    private var dDayFooterText: String {
        repeatSetting.isRepeating
            ? String(localized: "이 발생분의 날짜를 기준으로 계산합니다. 일정 목록과 위젯은 항상 각 시점의 다음 발생일을 기준으로 표시합니다.")
            : String(localized: "일정 시작 날짜를 기준으로 남은 일수를 계산합니다.")
    }

    /// event가 있고(기존 일정 편집) 그 반복 설정이 "반복 안 함"이 아니면 true. 새 일정이거나
    /// 반복하지 않는 일정에는 "시리즈" 개념이 없다.
    private var isExistingRepeatingSeries: Bool {
        guard let event else { return false }
        return event.repeatUnit != EventRepeatUnit.none.rawValue
    }

    /// 반복 시리즈의 특정 발생분만 수정하는 중인지. 반복 설정·D-Day 등 시리즈 전역 설정을
    /// 숨기거나 읽기 전용으로 바꿀 때 기준으로 쓴다.
    private var isEditingSingleOccurrenceOfRepeatingSeries: Bool {
        isExistingRepeatingSeries && editScope == .singleOccurrence
    }

    private var repeatInterval: Binding<Int> {
        Binding(
            get: { repeatSetting.interval },
            set: { repeatSetting.interval = max(1, $0) }
        )
    }

    private func saveEvent(
        exceptionPolicy: RecurringSeriesExceptionUpdatePolicy? = nil
    ) async {
        guard endDate >= startDate else {
            saveErrorMessage = String(localized: "종료 시간은 시작 시간보다 빠를 수 없습니다.")
            return
        }

        // 반복 종료일은 시작일보다 앞설 수 없다(날짜 단위 비교 — 종료일 당일은 포함이므로
        // 같은 날이면 유효하다). DatePicker의 in: 범위로도 막지만, 시작일을 종료일 선택 이후에
        // 바꿨을 수 있어 저장 직전에 한 번 더 확인한다. "이 일정만" 수정 중에는 반복 종료일
        // 자체를 바꾸지 않으므로(UI에서 숨김) 이 검사가 필요 없다.
        if !isEditingSingleOccurrenceOfRepeatingSeries, let repeatEndDate = effectiveRepeatEndDate {
            let calendar = Calendar.current
            guard calendar.startOfDay(for: repeatEndDate) >= calendar.startOfDay(for: startDate) else {
                saveErrorMessage = String(localized: "반복 종료 날짜는 시작일보다 빠를 수 없습니다.")
                return
            }
        }

        if event == nil, case .systemCalendar(let calendarIdentifier) = saveDestination {
            saveToSystemCalendar(calendarIdentifier)
            return
        }

        var seriesExceptions: [EventOccurrenceException] = []
        if let event, isExistingRepeatingSeries, editScope == .wholeSeries {
            seriesExceptions = fetchExceptions(for: event.id)
            let oldValues = RecurringSeriesValues(event: event)
            let newValues = pendingSeriesValues(for: event)

            switch RecurringSeriesExceptionUpdater.saveRequirement(
                exceptions: seriesExceptions,
                oldValues: oldValues,
                newValues: newValues
            ) {
            case .saveDirectly:
                break
            case .chooseUpdatePolicy:
                guard exceptionPolicy != nil else {
                    seriesExceptionChoice = .preserveIndividualChanges
                    isPresentingSeriesExceptionChoice = true
                    return
                }
            case .blockUnsafeRecurrenceChange:
                saveErrorMessage = String(localized: "반복 방식이나 간격을 변경하면 기존 개별 수정 및 삭제를 안전하게 연결할 수 없습니다. 기존 예외가 있는 동안에는 반복 방식과 간격을 변경할 수 없습니다.")
                return
            }
        }

        isSaving = true
        let savedEvent: Event

        if let event {
            if isEditingSingleOccurrenceOfRepeatingSeries {
                upsertSingleOccurrenceException(for: event)
            } else {
                update(
                    event,
                    exceptions: seriesExceptions,
                    exceptionPolicy: exceptionPolicy ?? .preserveIndividualChanges
                )
            }
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
                memo: notes,
                isDDayEnabled: isDDayEnabled,
                repeatEndDate: effectiveRepeatEndDate
            )
            modelContext.insert(newEvent)
            savedEvent = newEvent
        }

        do {
            try modelContext.save()
            WidgetReloadManager.reloadCalendar()
            await NotificationManager.shared.rescheduleNotifications(
                for: savedEvent,
                exceptions: fetchExceptions(for: savedEvent.id)
            )
            isSaving = false
            dismiss()
        } catch {
            modelContext.rollback()
            isSaving = false
            saveErrorMessage = String(localized: "저장 중 오류가 발생했습니다. 다시 시도해 주세요.")
        }
    }

    /// 방금 저장한 예외가 알림 재계산에 바로 반영되도록, @Query의 갱신 타이밍에 기대지 않고
    /// 저장 직후 모델 컨텍스트에서 직접 다시 읽는다.
    private func fetchExceptions(for eventID: UUID) -> [EventOccurrenceException] {
        let descriptor = FetchDescriptor<EventOccurrenceException>(
            predicate: #Predicate { $0.eventID == eventID }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// EventKit에 직접 저장한다. SwiftData와 로컬 알림(NotificationManager)은 사용하지 않는다.
    /// 실패하면 로컬로 대신 저장하지 않고 오류만 표시하며, 화면을 닫지 않아 입력 내용이 유지된다.
    private func saveToSystemCalendar(_ calendarIdentifier: String) {
        isSaving = true

        do {
            try systemCalendar.saveNewEvent(
                systemEventDraft,
                toCalendarWithIdentifier: calendarIdentifier
            )
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveErrorMessage = "\(error.message) 입력한 내용은 그대로 유지됩니다."
        }
    }

    private func update(
        _ event: Event,
        exceptions: [EventOccurrenceException],
        exceptionPolicy: RecurringSeriesExceptionUpdatePolicy
    ) {
        // 반복 일정의 원본이 아닌 이후 회차를 열었을 수 있으므로, 화면에 보여준 값을 그대로
        // event.startDate/endDate에 덮어쓰지 않는다. 대신 "열었을 때 보여준 값"과 "지금 입력값"의
        // 차이(delta)만큼만 시리즈 원본 시작·종료일을 옮긴다 — 반복이 아니거나 원본 회차를
        // 열었으면 두 값이 같아 delta가 0이라 기존과 똑같이 동작한다.
        let startDelta = startDate.timeIntervalSince(originalOccurrenceStartDate)
        let endDelta = endDate.timeIntervalSince(originalOccurrenceEndDate)
        let oldValues = RecurringSeriesValues(event: event)
        let newValues = pendingSeriesValues(for: event)

        event.title = title
        event.isAllDay = isAllDay
        event.startDate = event.startDate.addingTimeInterval(startDelta)
        event.endDate = event.endDate.addingTimeInterval(endDelta)
        event.color = eventColor.rawValue
        event.alarmOption = reminderSetting.option.rawValue
        event.alarmTimeIntervalBeforeStart = reminderSetting.timeIntervalBeforeStart
        event.alarmCustomValue = reminderSetting.customValue
        event.alarmCustomUnit = reminderSetting.customUnit.rawValue
        event.repeatUnit = repeatSetting.unit.rawValue
        event.repeatInterval = repeatSetting.interval
        event.memo = notes
        event.isDDayEnabled = isDDayEnabled
        event.repeatEndDate = effectiveRepeatEndDate

        RecurringSeriesExceptionUpdater.apply(
            from: oldValues,
            to: newValues,
            policy: exceptionPolicy,
            exceptions: exceptions
        )
    }

    /// 편집 중인 발생분의 delta를 시리즈 원본 날짜에 적용해 저장될 전체 일정 값을 만든다.
    private func pendingSeriesValues(for event: Event) -> RecurringSeriesValues {
        let startDelta = startDate.timeIntervalSince(originalOccurrenceStartDate)
        let endDelta = endDate.timeIntervalSince(originalOccurrenceEndDate)

        return RecurringSeriesValues(
            title: title,
            isAllDay: isAllDay,
            startDate: event.startDate.addingTimeInterval(startDelta),
            endDate: event.endDate.addingTimeInterval(endDelta),
            color: eventColor.rawValue,
            alarmOption: reminderSetting.option.rawValue,
            alarmTimeIntervalBeforeStart: reminderSetting.timeIntervalBeforeStart,
            alarmCustomValue: reminderSetting.customValue,
            alarmCustomUnit: reminderSetting.customUnit.rawValue,
            repeatUnit: repeatSetting.unit.rawValue,
            repeatInterval: repeatSetting.interval,
            memo: notes
        )
    }

    /// 반복 시리즈의 특정 발생분만 수정한다(Step 5-2 개별 수정). 원본 Event는 전혀 건드리지
    /// 않고, 이 발생분(exceptionKeyDate로 식별)에 대한 예외 레코드만 만들거나 갱신한다. 이미
    /// 이 발생분의 예외가 있었으면(existingException) 새로 만들지 않고 그대로 갱신한다 — 같은
    /// 발생분에 중복 레코드가 쌓이지 않게 한다.
    private func upsertSingleOccurrenceException(for event: Event) {
        let exception = existingException ?? EventOccurrenceException(
            eventID: event.id,
            originalOccurrenceStartDate: exceptionKeyDate,
            isExcluded: false
        )

        if existingException == nil {
            modelContext.insert(exception)
        }

        exception.isExcluded = false
        exception.overrideTitle = title
        exception.overrideIsAllDay = isAllDay
        exception.overrideStartDate = startDate
        exception.overrideEndDate = endDate
        exception.overrideColor = eventColor.rawValue
        exception.overrideAlarmOption = reminderSetting.option.rawValue
        exception.overrideAlarmTimeIntervalBeforeStart = reminderSetting.timeIntervalBeforeStart
        exception.overrideAlarmCustomValue = reminderSetting.customValue
        exception.overrideAlarmCustomUnit = reminderSetting.customUnit.rawValue
        exception.overrideMemo = notes
    }

    private func deleteEvent() async {
        guard let event else {
            return
        }

        let eventID = event.id
        // 전체 삭제는 시리즈와 연결된 개별 수정·삭제 예외도 함께 정리한다(고아 레코드 방지).
        for exception in fetchExceptions(for: eventID) {
            modelContext.delete(exception)
        }
        modelContext.delete(event)

        do {
            try modelContext.save()
            WidgetReloadManager.reloadCalendar()
            await NotificationManager.shared.cancelNotifications(
                for: eventID
            )
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = String(localized: "삭제 중 오류가 발생했습니다. 다시 시도해 주세요.")
        }
    }

    /// 반복 시리즈에서 이 발생분만 제외한다(Step 5-2 개별 삭제). 원본 Event는 그대로 두고,
    /// 이 발생분을 가리키는 예외를 isExcluded = true로 표시(또는 새로 생성)한다.
    private func deleteSingleOccurrence() async {
        guard let event else {
            return
        }

        let exception = existingException ?? EventOccurrenceException(
            eventID: event.id,
            originalOccurrenceStartDate: exceptionKeyDate,
            isExcluded: true
        )

        if existingException == nil {
            modelContext.insert(exception)
        } else {
            exception.isExcluded = true
        }

        do {
            try modelContext.save()
            WidgetReloadManager.reloadCalendar()
            await NotificationManager.shared.rescheduleNotifications(
                for: event,
                exceptions: fetchExceptions(for: event.id)
            )
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = String(localized: "삭제 중 오류가 발생했습니다. 다시 시도해 주세요.")
        }
    }
}

#Preview {
    NavigationStack {
        EventEditorView(date: Date())
    }
    .modelContainer(for: [Event.self, EventOccurrenceException.self], inMemory: true)
}
