import SwiftUI

/// 설정 화면의 잠금화면 Today 위젯 개인정보 섹션.
/// 끄면 위젯에는 실제 일정 제목 대신 "일정 있음"(영문 "Event Scheduled") 문구만 표시된다. 기본값 ON.
struct TodayWidgetSettingsSection: View {
    @AppStorage(
        TodayWidgetConstants.showEventTitlesKey,
        store: SystemCalendarService.settingsStore
    ) private var showsEventTitles = true

    var body: some View {
        Section {
            Toggle("잠금화면 일정 제목 표시", isOn: $showsEventTitles)
                .onChange(of: showsEventTitles) { _, _ in
                    WidgetReloadManager.requestCalendarReload()
                }
        } header: {
            Text("잠금화면 위젯")
        } footer: {
            Text("끄면 잠금화면 Today 위젯에 실제 일정 제목 대신 \"일정 있음\"만 표시됩니다.")
        }
    }
}
