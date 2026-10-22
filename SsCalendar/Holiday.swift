import Foundation

struct Holiday: Identifiable, Hashable {
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

    var id: String {
        "\(Int(date.timeIntervalSince1970))-\(name)"
    }
}

struct HolidayFetchKey: Hashable, Sendable {
    let country: HolidayCountry
    let months: [HolidayMonth]
    let refreshGeneration: Int
}
