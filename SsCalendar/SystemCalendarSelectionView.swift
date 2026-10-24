import SwiftUI

/// 설정 > 표시할 캘린더 선택.
/// 모든 캘린더는 기본 ON이며, 사용자가 OFF로 바꾼 캘린더의 일정만 표시하지 않는다.
struct SystemCalendarSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    /// 첫 연동 직후 시트로 안내할 때 true. 완료 버튼을 보여준다.
    var isIntro = false

    private let service = SystemCalendarService.shared

    var body: some View {
        let groups = service.calendarGroups()

        Form {
            Section {
                Text("Ss캘린더는 공휴일을 별도로 표시합니다. 공휴일이 중복되면 목록에서 해당 공휴일 캘린더를 꺼주세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if groups.isEmpty {
                Section {
                    Text("표시할 수 있는 캘린더가 없습니다.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.calendars) { calendar in
                        Toggle(isOn: visibilityBinding(for: calendar.id)) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(calendar.color)
                                    .frame(width: 10, height: 10)

                                Text(calendar.title)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("표시할 캘린더 선택")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if isIntro {
                service.markSelectionIntroShown()
            }
        }
        .toolbar {
            if isIntro {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func visibilityBinding(for calendarID: String) -> Binding<Bool> {
        Binding(
            get: { service.isCalendarVisible(calendarID) },
            set: { service.setCalendar(calendarID, isVisible: $0) }
        )
    }
}

#Preview {
    NavigationStack {
        SystemCalendarSelectionView()
    }
}
