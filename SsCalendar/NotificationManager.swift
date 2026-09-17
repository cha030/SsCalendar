import Foundation
import UserNotifications

struct EventNotificationSchedule: Equatable {
    let identifier: String
    let fireDate: Date
    let title: String
}

enum EventNotificationPlanner {
    static let maximumScheduledOccurrences = 32

    static func identifierPrefix(for eventID: UUID) -> String {
        "sscalendar.event.\(eventID.uuidString)."
    }

    static func schedules(
        for event: Event,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [EventNotificationSchedule] {
        guard
            event.alarmOption != "없음",
            let alarmOffset = event.alarmTimeIntervalBeforeStart
        else {
            return []
        }

        let firstRelevantStart = now.addingTimeInterval(max(0, alarmOffset))
        guard let rangeEnd = calendar.date(
            byAdding: .year,
            value: 100,
            to: firstRelevantStart
        ) else {
            return []
        }

        let occurrences = EventOccurrenceService.occurrences(
            for: event,
            intersecting: DateInterval(
                start: firstRelevantStart,
                end: rangeEnd
            ),
            calendar: calendar,
            limit: maximumScheduledOccurrences + 1
        )

        return occurrences
            .compactMap { occurrence in
                let fireDate = occurrence.startDate.addingTimeInterval(
                    -alarmOffset
                )

                guard fireDate > now else {
                    return nil
                }

                return EventNotificationSchedule(
                    identifier: identifier(
                        eventID: event.id,
                        occurrenceStart: occurrence.startDate
                    ),
                    fireDate: fireDate,
                    title: event.title
                )
            }
            .prefix(maximumScheduledOccurrences)
            .map { $0 }
    }

    private static func identifier(
        eventID: UUID,
        occurrenceStart: Date
    ) -> String {
        let milliseconds = Int64(
            occurrenceStart.timeIntervalSince1970 * 1_000
        )
        return "\(identifierPrefix(for: eventID))\(milliseconds)"
    }
}

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center: UNUserNotificationCenter

    private override init() {
        center = .current()
        super.init()
    }

    func configure() {
        center.delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func rescheduleNotifications(for event: Event) async {
        await cancelNotifications(for: event.id)

        let schedules = EventNotificationPlanner.schedules(for: event)
        guard !schedules.isEmpty else {
            return
        }

        guard await authorizationGrantedIfNeeded() else {
            return
        }

        for schedule in schedules {
            let content = UNMutableNotificationContent()
            content.title = schedule.title
            content.body = "일정이 곧 시작됩니다."
            content.sound = .default

            var dateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: schedule.fireDate
            )
            dateComponents.timeZone = Calendar.current.timeZone

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: schedule.identifier,
                content: content,
                trigger: trigger
            )

            await add(request)
        }
    }

    func cancelNotifications(for eventID: UUID) async {
        let prefix = EventNotificationPlanner.identifierPrefix(
            for: eventID
        )
        let pendingIdentifiers = await pendingNotificationIdentifiers(
            withPrefix: prefix
        )

        if !pendingIdentifiers.isEmpty {
            center.removePendingNotificationRequests(
                withIdentifiers: pendingIdentifiers
            )
        }

        let deliveredIdentifiers = await deliveredNotificationIdentifiers(
            withPrefix: prefix
        )

        if !deliveredIdentifiers.isEmpty {
            center.removeDeliveredNotifications(
                withIdentifiers: deliveredIdentifiers
            )
        }
    }

    private func authorizationGrantedIfNeeded() async -> Bool {
        let settings = await notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) {
                granted,
                _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async {
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }

    private func pendingNotificationIdentifiers(
        withPrefix prefix: String
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(
                    returning: requests
                        .map(\.identifier)
                        .filter { $0.hasPrefix(prefix) }
                )
            }
        }
    }

    private func deliveredNotificationIdentifiers(
        withPrefix prefix: String
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(
                    returning: notifications
                        .map(\.request.identifier)
                        .filter { $0.hasPrefix(prefix) }
                )
            }
        }
    }
}
