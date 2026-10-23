import SwiftUI

/// 자체 일정의 상세·편집 진입을 담당하는 행.
struct LocalEventRow: View {
    let occurrence: CalendarDisplayOccurrence
    let dDayText: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ScheduleEventRowContent(
                occurrence: occurrence,
                dDayText: dDayText
            )
        }
        .buttonStyle(.plain)
    }
}

/// 외부 일정 표시와 기존 EventKit 상세 진입·외부 D-Day 메뉴를 담당하는 행.
struct ExternalEventRow: View {
    let occurrence: CalendarDisplayOccurrence
    let dDayText: String?
    let isAccessEnabled: Bool
    let isDDayEnabled: Bool
    let onOpen: () -> Void
    let onToggleDDay: () -> Void

    var body: some View {
        if isAccessEnabled {
            Button(action: onOpen) {
                ScheduleEventRowContent(
                    occurrence: occurrence,
                    dDayText: dDayText
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(action: onToggleDDay) {
                    if isDDayEnabled {
                        Label("D-Day 해제", systemImage: "flag.slash")
                    } else {
                        Label("D-Day 설정", systemImage: "flag")
                    }
                }
            }
        } else {
            ScheduleEventRowContent(
                occurrence: occurrence,
                dDayText: dDayText
            )
        }
    }
}

private struct ScheduleEventRowContent: View {
    let occurrence: CalendarDisplayOccurrence
    let dDayText: String?

    private var eventColor: Color {
        occurrence.color
    }

    private var timeDescription: String {
        if occurrence.isAllDay {
            return String(localized: "종일")
        }

        if DeviceCalendar.current.isDate(
            occurrence.startDate,
            inSameDayAs: occurrence.endDate
        ) {
            let timeStyle = Date.FormatStyle()
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
                .locale(Locale.current)
            let startTime = occurrence.startDate.formatted(timeStyle)
            let endTime = occurrence.endDate.formatted(timeStyle)
            return "\(startTime) – \(endTime)"
        }

        let dateTimeStyle = Date.FormatStyle()
            .month(.defaultDigits)
            .day(.defaultDigits)
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
            .locale(Locale.current)
        let startDateTime = occurrence.startDate.formatted(dateTimeStyle)
        let endDateTime = occurrence.endDate.formatted(dateTimeStyle)
        return "\(startDateTime) – \(endDateTime)"
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(eventColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(timeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if case .system(let calendarTitle, _) = occurrence.source {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                        Text(
                            calendarTitle.isEmpty
                                ? String(localized: "iPhone 캘린더")
                                : calendarTitle
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let dDayText {
                Text(dDayText)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange))
            }

            if let markerSymbol = importantMarkerSymbol {
                Image(systemName: markerSymbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ImportantMarkerStyle.gold)
                    .accessibilityLabel(Text(importantMarkerAccessibilityLabel))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var importantMarkerSymbol: String? {
        switch occurrence.importantMarker {
        case .none: return nil
        case .star: return "star"
        case .sun: return "sun.max"
        }
    }

    private var importantMarkerAccessibilityLabel: String {
        switch occurrence.importantMarker {
        case .none: return ""
        case .star: return String(localized: "중요한 일정: 별")
        case .sun: return String(localized: "중요한 일정: 태양")
        }
    }
}
