import Foundation

enum HolidayDisplayFormatter {
    static func title(for names: [String], on date: Date) -> String? {
        var displayedNames: [String] = []
        let lunarDate = LunarCalendarService.lunarDate(for: date)

        for name in names {
            guard shouldDisplay(name, lunarDate: lunarDate) else { continue }

            let displayName = normalizedName(name)
            guard !displayName.isEmpty, !displayedNames.contains(displayName) else {
                continue
            }
            displayedNames.append(displayName)
        }

        return displayedNames.isEmpty ? nil : displayedNames.joined(separator: "\n")
    }

    private static func shouldDisplay(_ name: String, lunarDate: LunarDate?) -> Bool {
        guard let lunarDate else { return true }

        if name == "설날" {
            return lunarDate.month == 1 && lunarDate.day == 1
        }

        if name == "추석" {
            return lunarDate.month == 8 && lunarDate.day == 15
        }

        return true
    }

    private static func normalizedName(_ name: String) -> String {
        if name == "1월1일" { return "신정" }
        if name == "기독탄신일" { return "크리스마스" }

        if let openingParenthesis = name.firstIndex(of: "(") {
            return "\(name[..<openingParenthesis])\n\(name[openingParenthesis...])"
        }

        guard name.count > 5 else { return name }
        let middleOffset = Int(ceil(Double(name.count) / 2))
        let middleIndex = name.index(name.startIndex, offsetBy: middleOffset)
        return "\(name[..<middleIndex])\n\(name[middleIndex...])"
    }
}
