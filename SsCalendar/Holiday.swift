import Foundation

struct Holiday: Identifiable, Hashable {
    let date: Date
    let name: String
    let isHoliday: Bool

    var id: String {
        "\(Int(date.timeIntervalSince1970))-\(name)"
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
