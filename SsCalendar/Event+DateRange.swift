import Foundation

extension Event {
    func occurs(on date: Date, calendar: Calendar) -> Bool {
        baseOccurrence.occurs(on: date, calendar: calendar)
    }

    func occupiedDayRange(calendar: Calendar) -> ClosedRange<Date> {
        baseOccurrence.occupiedDayRange(calendar: calendar)
    }

    private var baseOccurrence: EventOccurrence {
        EventOccurrence(
            event: self,
            startDate: startDate,
            endDate: endDate
        )
    }
}
