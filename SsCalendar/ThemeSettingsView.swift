import SwiftUI
import UIKit

struct ThemeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedThemeRawValue: String

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
        selectedThemeRawValue: .constant(AppTheme.system.rawValue)
    )
}
