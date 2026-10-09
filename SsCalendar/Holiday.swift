import Foundation

struct Holiday: Identifiable, Hashable {
    let date: Date
    let name: String
    let isHoliday: Bool

    var id: String {
        "\(Int(date.timeIntervalSince1970))-\(name)"
    }
}

struct HolidayFetchKey: Hashable, Sendable {
    let country: HolidayCountry
    let months: [HolidayMonth]
    let refreshGeneration: Int
}
