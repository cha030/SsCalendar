import Foundation

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
        (try? readPayload().months.values.flatMap { $0 }) ?? []
    }

    @discardableResult
    static func store(
        _ records: [SharedHolidayRecord],
        year: Int,
        month: Int
    ) throws -> Bool {
        var payload = try readPayload()
        let key = String(format: "%04d-%02d", year, month)
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

enum SharedHolidayCacheError: Error {
    case appGroupUnavailable
}
