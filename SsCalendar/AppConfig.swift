import Foundation

enum AppConfig {
    static var holidayAPIKey: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "HOLIDAY_API_KEY"
        ) as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard
            !trimmedValue.isEmpty,
            !trimmedValue.hasPrefix("$(")
        else {
            return nil
        }

        return trimmedValue
    }
}
