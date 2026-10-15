import Foundation

enum HolidayDisplayFormatter {
    static func title(for names: [String], on date: Date) -> String? {
        var displayedNames: [String] = []
        let lunarDate = LunarCalendarService.lunarDate(for: date)

        for name in names {
            guard shouldDisplay(name, lunarDate: lunarDate) else { continue }

            let displayName = normalizedName(localizedName(name))
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

        // 공백이 있는 이름(영어 등): 가운데에 가장 가까운 공백에서만 줄바꿈
        if name.contains(" ") {
            let middle = name.count / 2
            let spaces = name.indices.filter { name[$0] == " " }
            if let best = spaces.min(by: {
                abs(name.distance(from: name.startIndex, to: $0) - middle)
                    < abs(name.distance(from: name.startIndex, to: $1) - middle)
            }) {
                return "\(name[..<best])\n\(name[name.index(after: best)...])"
            }
        }

        // 공백 없는 영어 단어: 단어 중간을 자르지 않고 그대로 둠
        if name.allSatisfy({ $0.isASCII }) { return name }

        // 한글 등: 기존처럼 가운데에서 분할
        let middleOffset = Int(ceil(Double(name.count) / 2))
        let middleIndex = name.index(name.startIndex, offsetBy: middleOffset)
        return "\(name[..<middleIndex])\n\(name[middleIndex...])"
    }

    private static func localizedName(_ name: String) -> String {
        if name.hasPrefix("대체공휴일(") || name.hasPrefix("대체공휴일 (")
            || name.hasPrefix("대체 공휴일(") || name.hasPrefix("대체 공휴일 ("),
           let openingParenthesis = name.firstIndex(of: "(") {
            return "\(String(localized: "대체공휴일"))\(name[openingParenthesis...])"
        }

        switch name {
        case "1월1일":
            return String(localized: "신정")
        case "기독탄신일":
            return String(localized: "크리스마스")
        case "신정":
            return String(localized: "신정")
        case "설날":
            return String(localized: "설날")
        case "삼일절":
            return String(localized: "삼일절")
        case "어린이날":
            return String(localized: "어린이날")
        case "부처님오신날":
            return String(localized: "부처님오신날")
        case "현충일":
            return String(localized: "현충일")
        case "광복절":
            return String(localized: "광복절")
        case "개천절":
            return String(localized: "개천절")
        case "한글날":
            return String(localized: "한글날")
        case "크리스마스":
            return String(localized: "크리스마스")
        case "추석":
            return String(localized: "추석")
        case "대체공휴일", "대체 공휴일":
            return String(localized: "대체공휴일")
        case "노동절", "근로자의날", "근로자의 날":
            return String(localized: "노동절")
        case "제헌절":
            return String(localized: "제헌절")
        case "임시공휴일":
            return String(localized: "임시공휴일")
        case "선거일":
            return String(localized: "선거일")
        case "대통령 선거일", "대통령선거일", "대통령 선거", "대통령선거":
            return String(localized: "대통령 선거일")
        case "전국동시지방선거일", "전국 동시 지방 선거일", "전국동시지방선거", "전국 동시 지방 선거":
            return String(localized: "전국동시지방선거일")
        case "국회의원선거일", "국회의원 선거일":
            return String(localized: "국회의원선거일")
        default:
            return name
        }
    }
}
