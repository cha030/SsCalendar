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
        calendar: Calendar = .current,
        exceptions: [EventOccurrenceException] = []
    ) -> [EventNotificationSchedule] {
        // 시리즈 알림이 꺼져 있어도 특정 발생분이 개별 수정으로 알림을 따로 켰을 수 있으므로,
        // 시리즈 단위로 미리 걸러내지 않고 발생분마다 각자의(override 포함) 알림 설정을 본다.
        guard let rangeEnd = calendar.date(
            byAdding: .year,
            value: 100,
            to: now
        ) else {
            return []
        }

        let occurrences = EventOccurrenceService.occurrences(
            for: event,
            intersecting: DateInterval(
                start: now,
                end: rangeEnd
            ),
            calendar: calendar,
            limit: maximumScheduledOccurrences + 1,
            exceptions: exceptions
        )

        return occurrences
            .compactMap { occurrence -> EventNotificationSchedule? in
                let alarmOption = occurrence.exception?.overrideAlarmOption ?? event.alarmOption
                guard
                    alarmOption != "없음",
                    let alarmOffset = occurrence.exception?.overrideAlarmTimeIntervalBeforeStart
                        ?? event.alarmTimeIntervalBeforeStart
                else {
                    return nil
                }

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
                    title: occurrence.title
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

    func rescheduleNotifications(
        for event: Event,
        exceptions: [EventOccurrenceException] = []
    ) async {
        await cancelNotifications(for: event.id)

        let schedules = EventNotificationPlanner.schedules(for: event, exceptions: exceptions)
        guard !schedules.isEmpty else {
            return
        }

        guard await authorizationGrantedIfNeeded() else {
            return
        }

        for schedule in schedules {
            let content = UNMutableNotificationContent()
            content.title = schedule.title
            content.body = String(localized: "일정이 곧 시작됩니다.")
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
