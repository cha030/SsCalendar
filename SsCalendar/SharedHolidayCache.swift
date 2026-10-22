import Foundation

enum HolidayCountry: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case southKorea = "kr"
    case unitedStates = "us"

    static let storageKey = "holidayCountry"
    static let settingsStore = UserDefaults(
        suiteName: SharedModelContainer.appGroupIdentifier
    ) ?? .standard

    var id: Self { self }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .southKorea: "대한민국"
        case .unitedStates: "미국"
        }
    }

    /// 주말(토요일/일요일) 날짜 숫자·요일 머리글을 평일과 다른 색으로 구분해 표시하는지.
    /// 공휴일 표시(빨강)는 이 값과 무관하게 항상 유지된다.
    var usesColoredWeekends: Bool {
        self == .southKorea
    }

    var usesColoredWeekendsForDisplay: Bool {
        usesColoredWeekends(in: Self.settingsStore)
    }

    func usesColoredWeekends(in defaults: UserDefaults) -> Bool {
        switch self {
        case .southKorea:
            true
        case .unitedStates:
            USWeekendColorSetting.selected(in: defaults).usesColoredWeekends
        }
    }

    static func selected(in defaults: UserDefaults) -> Self {
        guard
            let rawValue = defaults.string(forKey: storageKey),
            let country = Self(rawValue: rawValue)
        else {
            return HolidayCountry.defaultCountry
        }

        return country
    }
}

extension HolidayCountry {
    static func defaultCountry(for region: Locale.Region?) -> HolidayCountry {
        region?.identifier == "KR" ? .southKorea : .unitedStates
    }

    static var defaultCountry: HolidayCountry {
        defaultCountry(for: Locale.current.region)
    }
}

enum USWeekendColorSetting: String, CaseIterable, Identifiable, Sendable {
    case colored
    case monochrome

    static let storageKey = "usWeekendColorSetting"
    static let defaultValue = Self.monochrome

    var id: Self { self }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .colored: "색상 표시"
        case .monochrome: "무채색 표시"
        }
    }

    var usesColoredWeekends: Bool {
        self == .colored
    }

    static func selected(in defaults: UserDefaults) -> Self {
        guard
            let rawValue = defaults.string(forKey: storageKey),
            let setting = Self(rawValue: rawValue)
        else {
            return defaultValue
        }

        return setting
    }
}

enum LunarDisplaySetting {
    nonisolated static let storageKey = "showLunarDates"

    nonisolated static var store: UserDefaults {
        UserDefaults(suiteName: SharedModelContainer.appGroupIdentifier) ?? .standard
    }

    /// 저장된 값이 없으면 false(숨김). @AppStorage 기본값(false)과 항상 같다.
    nonisolated static var isEnabled: Bool {
        store.bool(forKey: storageKey)
    }
}

enum CalendarTextSizeSetting {
    nonisolated static let storageKey = "calendarTextSizeLevel"

    nonisolated static var store: UserDefaults {
        UserDefaults(suiteName: SharedModelContainer.appGroupIdentifier) ?? .standard
    }

    /// 값이 없거나 0...3 범위를 벗어나면 0(보통)으로 처리한다. @AppStorage 기본값(0)과 항상 같다.
    nonisolated static var level: Int {
        let stored = store.integer(forKey: storageKey)
        return (0...3).contains(stored) ? stored : 0
    }
}

struct HolidayMonth: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int

    static func < (lhs: HolidayMonth, rhs: HolidayMonth) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }

        return lhs.month < rhs.month
    }
}

struct SharedHolidayRecord: Codable, Hashable, Sendable {
    let date: Date
    let year: Int
    let month: Int
    let day: Int
    let name: String
    let isHoliday: Bool

    init(date: Date, name: String, isHoliday: Bool, calendar: Calendar = DeviceCalendar.current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.date = date
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
        self.name = name
        self.isHoliday = isHoliday
    }

    init(year: Int, month: Int, day: Int, name: String, isHoliday: Bool, calendar: Calendar = DeviceCalendar.current) {
        self.date = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
        self.year = year
        self.month = month
        self.day = day
        self.name = name
        self.isHoliday = isHoliday
    }
}

@MainActor
enum SharedHolidayCache {
    private struct Payload: Codable {
        let version: Int
        var months: [String: [SharedHolidayRecord]] = [:]

        init(months: [String: [SharedHolidayRecord]] = [:]) {
            version = 2
            self.months = months
        }
    }

    private static let relativePath = "Library/Caches/Holidays/holidays.json"

    static func records() -> [SharedHolidayRecord] {
        records(for: .southKorea)
    }

    static func records(for country: HolidayCountry) -> [SharedHolidayRecord] {
        guard let payload = try? readPayload() else { return [] }

        let prefix = "\(country.rawValue)-"
        return payload.months.flatMap { key, records in
            if key.hasPrefix(prefix) {
                return records
            }

            return []
        }
    }

    @discardableResult
    static func store(
        _ records: [SharedHolidayRecord],
        country: HolidayCountry,
        year: Int,
        month: Int
    ) throws -> Bool {
        var payload = try readPayload()
        let key = String(
            format: "%@-%04d-%02d",
            country.rawValue,
            year,
            month
        )
        let normalizedRecords = records.sorted(by: recordSort)

        guard payload.months[key] != normalizedRecords else {
            return false
        }

        payload.months[key] = normalizedRecords
        let url = try cacheURL()
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
        return true
    }

    private static func readPayload() throws -> Payload {
        let url = try cacheURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Payload()
        }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
            guard payload.version == 2 else { throw SharedHolidayCacheError.staleCache }
            return payload
        } catch {
            try? FileManager.default.removeItem(at: url)
            return Payload()
        }
    }

    private static func cacheURL() throws -> URL {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupIdentifier
        ) else {
            throw SharedHolidayCacheError.appGroupUnavailable
        }

        let url = groupURL.appending(
            path: relativePath,
            directoryHint: .notDirectory
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return url
    }

    private static func recordSort(
        _ lhs: SharedHolidayRecord,
        _ rhs: SharedHolidayRecord
    ) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        return lhs.name < rhs.name
    }
}

/// 미국 연방 공휴일을 날짜 전용 값으로 계산한다.
/// 공휴일은 연·월·일을 보존해 앱과 위젯의 기기 시간대에서 같은 날짜로 매칭한다.
enum USFederalHolidayCalculator {
    static func records(
        for month: HolidayMonth,
        calendar: Calendar = DeviceCalendar.current
    ) -> [SharedHolidayRecord] {

        let years = [month.year - 1, month.year, month.year + 1]
        var records: Set<SharedHolidayRecord> = []

        for year in years {
            for holiday in holidays(in: year, calendar: calendar) {
                guard
                    holiday.year == month.year,
                    holiday.month == month.month
                else {
                    continue
                }
                records.insert(holiday)
            }
        }

        return records.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year < rhs.year }
            if lhs.month != rhs.month { return lhs.month < rhs.month }
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            return lhs.name < rhs.name
        }
    }

    private static func holidays(
        in year: Int,
        calendar: Calendar
    ) -> [SharedHolidayRecord] {
        var result: [SharedHolidayRecord] = []

        func appendFixed(
            month: Int,
            day: Int,
            name: String,
            availableFrom: Int? = nil
        ) {
            if let availableFrom, year < availableFrom { return }
            guard let date = date(year: year, month: month, day: day, calendar: calendar) else {
                return
            }

            result.append(SharedHolidayRecord(date: date, name: name, isHoliday: true, calendar: calendar))

            let weekday = calendar.component(.weekday, from: date)
            let observedOffset: Int?
            switch weekday {
            case 7: observedOffset = -1 // Saturday → Friday
            case 1: observedOffset = 1  // Sunday → Monday
            default: observedOffset = nil
            }

            if let observedOffset,
               let observedDate = calendar.date(byAdding: .day, value: observedOffset, to: date) {
                result.append(
                    SharedHolidayRecord(
                        date: observedDate,
                        name: String(localized: "\(name) (Observed)"),
                        isHoliday: true,
                        calendar: calendar
                    )
                )
            }
        }

        appendFixed(month: 1, day: 1, name: String(localized: "New Year's Day"))
        appendFixed(month: 6, day: 19, name: String(localized: "Juneteenth"), availableFrom: 2021)
        appendFixed(month: 7, day: 4, name: String(localized: "Independence Day"))
        appendFixed(month: 11, day: 11, name: String(localized: "Veterans Day"))
        appendFixed(month: 12, day: 25, name: String(localized: "Christmas Day"))

        appendMovable(
            date: nthWeekday(of: year, month: 1, weekday: 2, ordinal: 3, calendar: calendar),
            name: String(localized: "Martin Luther King Jr. Day"),
            calendar: calendar,
            to: &result
        )
        appendMovable(
            date: nthWeekday(of: year, month: 2, weekday: 2, ordinal: 3, calendar: calendar),
            name: String(localized: "Washington's Birthday"),
            calendar: calendar,
            to: &result
        )
        appendMovable(
            date: lastWeekday(of: year, month: 5, weekday: 2, calendar: calendar),
            name: String(localized: "Memorial Day"),
            calendar: calendar,
            to: &result
        )
        appendMovable(
            date: nthWeekday(of: year, month: 9, weekday: 2, ordinal: 1, calendar: calendar),
            name: String(localized: "Labor Day"),
            calendar: calendar,
            to: &result
        )
        appendMovable(
            date: nthWeekday(of: year, month: 10, weekday: 2, ordinal: 2, calendar: calendar),
            name: String(localized: "Columbus Day"),
            calendar: calendar,
            to: &result
        )
        appendMovable(
            date: nthWeekday(of: year, month: 11, weekday: 5, ordinal: 4, calendar: calendar),
            name: String(localized: "Thanksgiving Day"),
            calendar: calendar,
            to: &result
        )

        return result
    }

    private static func appendMovable(
        date: Date?,
        name: String,
        calendar: Calendar,
        to records: inout [SharedHolidayRecord]
    ) {
        guard let date else { return }
        records.append(SharedHolidayRecord(date: date, name: name, isHoliday: true, calendar: calendar))
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func nthWeekday(
        of year: Int,
        month: Int,
        weekday: Int,
        ordinal: Int,
        calendar: Calendar
    ) -> Date? {
        guard
            let first = date(year: year, month: month, day: 1, calendar: calendar),
            let firstWeekday = calendar.dateComponents([.weekday], from: first).weekday
        else { return nil }

        let offset = (weekday - firstWeekday + 7) % 7 + (ordinal - 1) * 7
        return calendar.date(byAdding: .day, value: offset, to: first)
    }

    private static func lastWeekday(
        of year: Int,
        month: Int,
        weekday: Int,
        calendar: Calendar
    ) -> Date? {
        guard
            let nextMonth = calendar.date(
                from: DateComponents(year: year, month: month + 1, day: 1)
            ),
            let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth),
            let lastWeekday = calendar.dateComponents([.weekday], from: lastDay).weekday
        else { return nil }

        let offset = (lastWeekday - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: lastDay)
    }
}

enum SharedHolidayCacheError: Error {
    case appGroupUnavailable
    case staleCache
}
