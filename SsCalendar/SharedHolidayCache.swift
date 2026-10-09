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

    static func selected(in defaults: UserDefaults) -> Self {
        guard
            let rawValue = defaults.string(forKey: storageKey),
            let country = Self(rawValue: rawValue)
        else {
            return .southKorea
        }

        return country
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
    let name: String
    let isHoliday: Bool
}

@MainActor
enum SharedHolidayCache {
    private struct Payload: Codable {
        var months: [String: [SharedHolidayRecord]] = [:]
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

            // 이전 버전의 한국 캐시(예: 2026-10)는 한국 데이터로만 해석한다.
            if country == .southKorea,
               key.count == 7,
               payload.months["\(prefix)\(key)"] == nil {
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

        return try JSONDecoder().decode(
            Payload.self,
            from: Data(contentsOf: url)
        )
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
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.name < rhs.name
    }
}

/// 미국 연방 공휴일을 날짜 전용 값으로 계산한다.
/// 모든 날짜는 앱과 위젯의 기존 날짜 기준(Asia/Seoul 자정)으로 생성하므로
/// 공휴일 표시가 미국 시간대의 시각 변환 때문에 하루 밀리지 않는다.
enum USFederalHolidayCalculator {
    private static let timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current

    static func records(for month: HolidayMonth) -> [SharedHolidayRecord] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let years = [month.year - 1, month.year, month.year + 1]
        var records: Set<SharedHolidayRecord> = []

        for year in years {
            for holiday in holidays(in: year, calendar: calendar) {
                let holidayComponents = calendar.dateComponents(
                    [.year, .month],
                    from: holiday.date
                )
                guard
                    holidayComponents.year == month.year,
                    holidayComponents.month == month.month
                else {
                    continue
                }
                records.insert(holiday)
            }
        }

        return records.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
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

            result.append(SharedHolidayRecord(date: date, name: name, isHoliday: true))

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
                        isHoliday: true
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
            to: &result
        )
        appendMovable(
            date: nthWeekday(of: year, month: 2, weekday: 2, ordinal: 3, calendar: calendar),
            name: String(localized: "Washington's Birthday"),
            to: &result
        )
        appendMovable(
            date: lastWeekday(of: year, month: 5, weekday: 2, calendar: calendar),
            name: String(localized: "Memorial Day"),
            to: &result
        )
        appendMovable(
            date: nthWeekday(of: year, month: 9, weekday: 2, ordinal: 1, calendar: calendar),
            name: String(localized: "Labor Day"),
            to: &result
        )
        appendMovable(
            date: nthWeekday(of: year, month: 10, weekday: 2, ordinal: 2, calendar: calendar),
            name: String(localized: "Columbus Day"),
            to: &result
        )
        appendMovable(
            date: nthWeekday(of: year, month: 11, weekday: 5, ordinal: 4, calendar: calendar),
            name: String(localized: "Thanksgiving Day"),
            to: &result
        )

        return result
    }

    private static func appendMovable(
        date: Date?,
        name: String,
        to records: inout [SharedHolidayRecord]
    ) {
        guard let date else { return }
        records.append(SharedHolidayRecord(date: date, name: name, isHoliday: true))
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
}
