import SwiftUI
import WidgetKit

struct SsCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CalendarWidgetConstants.kind,
            provider: CalendarWidgetProvider()
        ) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("월간 캘린더")
        .description("이번 달 날짜와 저장된 일정을 한눈에 확인합니다.")
        .supportedFamilies([
            .systemMedium,
            .systemLarge,
            .systemExtraLargePortrait
        ])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.previewEntry
}

#Preview(as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.previewEntry
}

#Preview("4주 Large", as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.emptyEntry(
        for: CalendarWidgetCalendar.korean.date(
            from: DateComponents(year: 2026, month: 2, day: 1)
        ) ?? .now
    )
}

#Preview("6주 Large", as: .systemLarge) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.emptyEntry(
        for: CalendarWidgetCalendar.korean.date(
            from: DateComponents(year: 2026, month: 8, day: 1)
        ) ?? .now
    )
}

#Preview("Extra Large Portrait", as: .systemExtraLargePortrait) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.previewEntry
}

#Preview("4주 Extra Large Portrait", as: .systemExtraLargePortrait) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.emptyEntry(
        for: CalendarWidgetCalendar.korean.date(
            from: DateComponents(year: 2026, month: 2, day: 1)
        ) ?? .now
    )
}

#Preview("6주 Extra Large Portrait", as: .systemExtraLargePortrait) {
    SsCalendarWidget()
} timeline: {
    CalendarWidgetCalendar.emptyEntry(
        for: CalendarWidgetCalendar.korean.date(
            from: DateComponents(year: 2026, month: 8, day: 1)
        ) ?? .now
    )
}
