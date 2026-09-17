import SwiftData
import SwiftUI

struct DayScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Event.startDate, order: .forward) private var events: [Event]
    @State private var isPresentingEventEditor = false
    @State private var selectedEvent: Event?

    let date: Date

    private var dateTitle: String {
        date.formatted(
            Date.FormatStyle()
                .month(.defaultDigits)
                .day()
                .weekday(.wide)
                .locale(Locale(identifier: "ko_KR"))
        )
    }

    private var orderedOccurrences: [EventOccurrence] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        guard let nextDayStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: dayStart
        ) else {
            return []
        }

        return EventOccurrenceService.occurrences(
            for: events,
            intersecting: DateInterval(
                start: dayStart,
                end: nextDayStart
            ),
            calendar: calendar
        )
    }

    var body: some View {
        ZStack {
            List {
                ForEach(orderedOccurrences) { occurrence in
                    Button {
                        selectedEvent = occurrence.event
                    } label: {
                        EventRow(occurrence: occurrence)
                    }
                    .buttonStyle(.plain)
                }
            }

            if orderedOccurrences.isEmpty {
                Text("일정이 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("뒤로가기")
            }

            ToolbarItem(placement: .principal) {
                Text(dateTitle)
                    .font(.headline)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingEventEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("일정 추가")
            }
        }
        .sheet(isPresented: $isPresentingEventEditor) {
            NavigationStack {
                EventEditorView(date: date)
            }
        }
        .sheet(item: $selectedEvent) { event in
            NavigationStack {
                EventEditorView(date: event.startDate, event: event)
            }
        }
    }
}

private struct EventRow: View {
    let occurrence: EventOccurrence

    private var eventColor: Color {
        EventColor(rawValue: occurrence.event.color)?.color ?? .gray
    }

    private var timeDescription: String {
        if occurrence.isAllDay {
            return "종일"
        }

        if Calendar.current.isDate(
            occurrence.startDate,
            inSameDayAs: occurrence.endDate
        ) {
            let timeStyle = Date.FormatStyle()
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
                .locale(Locale(identifier: "ko_KR"))
            let startTime = occurrence.startDate.formatted(timeStyle)
            let endTime = occurrence.endDate.formatted(timeStyle)
            return "\(startTime) – \(endTime)"
        }

        let dateTimeStyle = Date.FormatStyle()
            .month(.defaultDigits)
            .day(.defaultDigits)
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
            .locale(Locale(identifier: "ko_KR"))
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
                Text(occurrence.event.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(timeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        DayScheduleView(date: Date())
    }
    .modelContainer(for: Event.self, inMemory: true)
}
