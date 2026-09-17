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
        createdAt: Date = Date()
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
    }
}
