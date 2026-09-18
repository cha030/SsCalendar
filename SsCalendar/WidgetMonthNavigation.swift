import AppIntents
import Foundation
import WidgetKit

@MainActor
enum WidgetMonthState {
    private static let selectedMonthKey = "widgetSelectedMonthIndex"
    private static let selectedDateKey = "widgetSelectedDate"

    static func displayedMonthStart(now: Date = Date()) -> Date {
        let calendar = koreanCalendar
        let current = monthIndex(for: now, calendar: calendar)
        let selected = sharedDefaults?.object(forKey: selectedMonthKey) as? Int
        return monthStart(for: selected ?? current, calendar: calendar) ?? now
    }

    @discardableResult
    static func move(by value: Int, now: Date = Date()) -> Bool {
        guard value != 0, let defaults = sharedDefaults else { return false }
        let calendar = koreanCalendar
        let current = monthIndex(for: now, calendar: calendar)
        let selected = defaults.object(forKey: selectedMonthKey) as? Int
        defaults.set((selected ?? current) + value, forKey: selectedMonthKey)
        return true
    }

    @discardableResult
    static func returnToCurrentMonth(now: Date = Date()) -> Bool {
        guard let defaults = sharedDefaults else { return false }
        let calendar = koreanCalendar
        let current = monthIndex(for: now, calendar: calendar)
        guard let selected = defaults.object(forKey: selectedMonthKey) as? Int,
              selected != current else {
            if defaults.object(forKey: selectedMonthKey) != nil {
                defaults.removeObject(forKey: selectedMonthKey)
            }
            return false
        }

        defaults.removeObject(forKey: selectedMonthKey)
        return true
    }

    static func selectedDate() -> Date? {
        sharedDefaults?.object(forKey: selectedDateKey) as? Date
    }

    @discardableResult
    static func select(date: Date) -> Bool {
        guard let defaults = sharedDefaults else { return false }
        let normalizedDate = koreanCalendar.startOfDay(for: date)
        if let selected = defaults.object(forKey: selectedDateKey) as? Date,
           koreanCalendar.isDate(selected, inSameDayAs: normalizedDate) {
            return false
        }
        defaults.set(normalizedDate, forKey: selectedDateKey)
        return true
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: SharedModelContainer.appGroupIdentifier)
    }

    private static var koreanCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }

    private static func monthIndex(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 1
        let month = components.month ?? 1
        return year * 12 + month - 1
    }

    private static func monthStart(for index: Int, calendar: Calendar) -> Date? {
        let year = index >= 0 ? index / 12 : (index - 11) / 12
        let monthIndex = index - year * 12
        return calendar.date(
            from: DateComponents(year: year, month: monthIndex + 1, day: 1)
        )
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
