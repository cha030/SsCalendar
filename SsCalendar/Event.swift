import Foundation
import SwiftData

@Model
final class Event {
    @Attribute(.unique) var id: UUID
    var title: String
    var isAllDay: Bool
    var startDate: Date
    var endDate: Date
    var color: String
    var alarmOption: String
    var alarmTimeIntervalBeforeStart: TimeInterval?
    var alarmCustomValue: Int
    var alarmCustomUnit: String
    var repeatUnit: String
    var repeatInterval: Int
    var memo: String
    var createdAt: Date
    /// D-Day(남은 일수) 표시 여부(Step 5-2). 기본값 false라 기존에 저장된 일정도 SwiftData
    /// 경량 마이그레이션으로 안전하게 이 속성을 얻는다(추가 마이그레이션 계획 불필요).
    /// 항상 startDate를 기준으로 계산하며, 지난 일정이어도 이 값을 임의로 끄지 않는다.
    var isDDayEnabled: Bool = false
    /// 반복 종료 날짜(포함). nil이면 "종료 안 함"(기존 동작과 동일, 무기한 반복). 옵셔널이라
    /// 기존 저장 데이터는 자동으로 nil을 얻어 SwiftData 경량 마이그레이션으로 안전하다 — 기존
    /// 반복 일정은 전부 "종료 안 함" 상태를 그대로 유지한다. 반복하지 않는 일정에는 의미 없다.
    var repeatEndDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        isAllDay: Bool,
        startDate: Date,
        endDate: Date,
        color: String,
        alarmOption: String,
        alarmTimeIntervalBeforeStart: TimeInterval?,
        alarmCustomValue: Int,
        alarmCustomUnit: String,
        repeatUnit: String,
        repeatInterval: Int,
        memo: String,
        createdAt: Date = Date(),
        isDDayEnabled: Bool = false,
        repeatEndDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isAllDay = isAllDay
        self.startDate = startDate
        self.endDate = endDate
        self.color = color
        self.alarmOption = alarmOption
        self.alarmTimeIntervalBeforeStart = alarmTimeIntervalBeforeStart
        self.alarmCustomValue = alarmCustomValue
        self.alarmCustomUnit = alarmCustomUnit
        self.repeatUnit = repeatUnit
        self.repeatInterval = repeatInterval
        self.memo = memo
        self.createdAt = createdAt
        self.isDDayEnabled = isDDayEnabled
        self.repeatEndDate = repeatEndDate
    }
}

enum AllDayDate {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    static func storageDate(for date: Date, calendar: Calendar = DeviceCalendar.current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return utcCalendar.date(from: components) ?? date
    }

    static func storageDate(year: Int, month: Int, day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    static func components(fromStorageDate date: Date) -> DateComponents {
        utcCalendar.dateComponents([.year, .month, .day], from: date)
    }

    static func normalizedStorageDate(_ date: Date) -> Date {
        let components = components(fromStorageDate: date)
        return utcCalendar.date(from: components) ?? date
    }

    static func displayDate(
        fromStorageDate date: Date,
        calendar: Calendar = DeviceCalendar.current
    ) -> Date {
        let components = components(fromStorageDate: date)
        return calendar.date(from: components) ?? date
    }
}
