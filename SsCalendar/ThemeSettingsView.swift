import SwiftUI
import UIKit

struct ThemeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedThemeRawValue: String
    @Binding var holidayCountryRawValue: String
    var onHolidayCountryChanged: () -> Void = {}
    @AppStorage(LunarDisplaySetting.storageKey, store: LunarDisplaySetting.store)
    private var showLunarDates = false
    @AppStorage(CalendarTextSizeSetting.storageKey, store: CalendarTextSizeSetting.store)
    private var calendarTextSizeLevel = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("화면 모드") {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            selectedThemeRawValue = theme.rawValue
                        } label: {
                            HStack {
                                Text(theme.title)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(
                                    systemName: selectedTheme == theme
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    selectedTheme == theme ? Color.accentColor : .secondary
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            selectedTheme == theme ? .isSelected : []
                        )
                    }
                }

                SystemCalendarSettingsSection()

                TodayWidgetSettingsSection()

                Section("공휴일 국가") {
                    Picker("공휴일 국가", selection: $holidayCountryRawValue) {
                        ForEach(HolidayCountry.allCases) { country in
                            Text(country.localizedTitle)
                                .tag(country.rawValue)
                        }
                    }
                    .onChange(of: holidayCountryRawValue) { _, _ in
                        WidgetReloadManager.requestCalendarReload()
                        onHolidayCountryChanged()
                    }
                }

                Section {
                    Toggle("음력 표시", isOn: $showLunarDates)
                        .onChange(of: showLunarDates) { _, _ in
                            WidgetReloadManager.requestCalendarReload()
                            onHolidayCountryChanged()
                        }
                }

                Section {
                    Picker("위젯 글자 크기", selection: $calendarTextSizeLevel) {
                        Text("보통").tag(0)
                        Text("크게").tag(1)
                        Text("더 크게").tag(2)
                        Text("가장 크게").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: calendarTextSizeLevel) { _, _ in
                        WidgetReloadManager.requestCalendarReload()
                    }
                } header: {
                    Text("위젯 글자 크기")
                } footer: {
                    Text("달력 위젯의 글자 크기를 바꿉니다. 크게 할수록 일정은 간단히 표시됩니다.")
                }

                Section("언어") {
                    Button {
                        openAppSettings()
                    } label: {
                        LabeledContent {
                            Text(currentAppLanguageName)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("앱 언어", systemImage: "globe")
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(resolvedColorScheme)
    }

    private var currentAppLanguageName: String {
        let languageCode = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: languageCode).localizedString(forLanguageCode: languageCode)
            ?? languageCode
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: selectedThemeRawValue) ?? .system
    }

    private var resolvedColorScheme: ColorScheme {
        if let preferredColorScheme = selectedTheme.preferredColorScheme {
            return preferredColorScheme
        }

        let interfaceStyle = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.traitCollection.userInterfaceStyle }
            .first ?? .unspecified
        return interfaceStyle == .dark ? .dark : .light
    }
}

#Preview {
    ThemeSettingsView(
        selectedThemeRawValue: .constant(AppTheme.system.rawValue),
        holidayCountryRawValue: .constant(HolidayCountry.southKorea.rawValue)
    )
}
