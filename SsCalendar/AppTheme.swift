import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "selectedAppTheme"

    var id: Self { self }

    var title: String {
        switch self {
        case .system:
            String(localized: "시스템")
        case .light:
            String(localized: "라이트")
        case .dark:
            String(localized: "다크")
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
