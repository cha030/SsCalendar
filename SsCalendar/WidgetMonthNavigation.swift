import AppIntents
import Foundation
import WidgetKit

@MainActor
enum WidgetMonthState {
    private static let selectedMonthKey = "widgetSelectedMonth"
    private static let selectedDateKey = "widgetSelectedDate"

    static func displayedMonthStart(now: Date = Date()) -> Date {
        let calendar = DeviceCalendar.current
        let current = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let selected = sharedDefaults?.string(forKey: selectedMonthKey).flatMap {
            date(from: $0, calendar: calendar)
        }
        return selected.flatMap { calendar.dateInterval(of: .month, for: $0)?.start } ?? current
    }

    @discardableResult
    static func move(by value: Int, now: Date = Date()) -> Bool {
        guard value != 0, let defaults = sharedDefaults else { return false }
        let calendar = DeviceCalendar.current
        let current = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let selected = defaults.string(forKey: selectedMonthKey).flatMap {
            date(from: $0, calendar: calendar)
        } ?? current
        guard let moved = calendar.date(byAdding: .month, value: value, to: selected) else {
            return false
        }
        let movedMonth = calendar.dateInterval(of: .month, for: moved)?.start ?? moved
        defaults.set(dateString(for: movedMonth, calendar: calendar), forKey: selectedMonthKey)
        return true
    }

    @discardableResult
    static func returnToCurrentMonth(now: Date = Date()) -> Bool {
        guard let defaults = sharedDefaults else { return false }
        let calendar = DeviceCalendar.current
        let current = calendar.dateInterval(of: .month, for: now)?.start ?? now
        guard let selected = defaults.string(forKey: selectedMonthKey).flatMap({
            date(from: $0, calendar: calendar)
        }),
        !calendar.isDate(selected, equalTo: current, toGranularity: .month) else {
            if defaults.object(forKey: selectedMonthKey) != nil {
                defaults.removeObject(forKey: selectedMonthKey)
            }
            return false
        }

        defaults.removeObject(forKey: selectedMonthKey)
        return true
    }

    static func selectedDate() -> Date? {
        guard let value = sharedDefaults?.string(forKey: selectedDateKey) else { return nil }
        return Self.date(from: value, calendar: DeviceCalendar.current)
    }

    @discardableResult
    static func select(date: Date) -> Bool {
        guard let defaults = sharedDefaults else { return false }
        let calendar = DeviceCalendar.current
        let normalizedDate = calendar.startOfDay(for: date)
        if let selected = defaults.string(forKey: selectedDateKey).flatMap({
            Self.date(from: $0, calendar: calendar)
        }), calendar.isDate(selected, inSameDayAs: normalizedDate) {
            return false
        }
        defaults.set(dateString(for: normalizedDate, calendar: calendar), forKey: selectedDateKey)
        return true
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: SharedModelContainer.appGroupIdentifier)
    }

    private static func dateString(for date: Date, calendar: Calendar) -> String {
        DeviceCalendar.dateFormatter(format: "yyyy-MM-dd", calendar: calendar).string(from: date)
    }

    private static func date(from value: String, calendar: Calendar) -> Date? {
        DeviceCalendar.dateFormatter(format: "yyyy-MM-dd", calendar: calendar).date(from: value)
    }
}

struct PreviousWidgetMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "이전 달"
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult {
        if await WidgetMonthState.move(by: -1) {
            await MainActor.run {
                WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
            }
        }
        return .result()
    }
}

struct NextWidgetMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "다음 달"
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult {
        if await WidgetMonthState.move(by: 1) {
            await MainActor.run {
                WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
            }
        }
        return .result()
    }
}

struct CurrentWidgetMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "현재 달"
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult {
        let now = Date()
        let monthChanged = await WidgetMonthState.returnToCurrentMonth(now: now)
        let selectionChanged = await WidgetMonthState.select(date: now)
        if monthChanged || selectionChanged {
            await MainActor.run {
                WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
            }
        }
        return .result()
    }
}

struct SelectWidgetDateIntent: AppIntent {
    static let title: LocalizedStringResource = "날짜 선택"
    static let supportedModes: IntentModes = .background

    @Parameter(title: "날짜")
    var date: Date

    init() {}

    init(date: Date) {
        self.date = date
    }

    func perform() async throws -> some IntentResult {
        if await WidgetMonthState.select(date: date) {
            await MainActor.run {
                WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
            }
        }
        return .result()
    }
}
