import Foundation
import OSLog
import SwiftData

@MainActor
enum SharedModelContainer {
    // 불변 상수라 격리할 상태가 없다. HolidayCountry.settingsStore처럼 이 타입의 MainActor 격리를
    // 공유하지 않는(예: 위젯 타깃의 기본 격리가 nonisolated인) 코드에서도 안전하게 참조할 수 있어야 한다.
    nonisolated static let appGroupIdentifier = "group.sscalendar"
    static let storeRelativePath =
        "Library/Application Support/SwiftData/SsCalendar.store"

    private static let migrationMarkerKey =
        "sharedSwiftDataMigrationCompleted"
    private static let logger = Logger(
        subsystem: "group.sscalendar",
        category: "SharedModelContainer"
    )

    static func makeSharedContainer() throws -> ModelContainer {
        let schema = Schema([Event.self])
        let storeURL = try sharedStoreURL()
        let configuration = ModelConfiguration(
            "Shared",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    static func makeAppContainer() throws -> ModelContainer {
        let sharedContainer = try makeSharedContainer()
        let defaults = try sharedUserDefaults()

        guard !defaults.bool(forKey: migrationMarkerKey) else {
            return sharedContainer
        }

        do {
            try migrateLegacyEventsIfNeeded(to: sharedContainer)
            defaults.set(true, forKey: migrationMarkerKey)
            return sharedContainer
        } catch {
            logger.error(
                "Legacy Event migration failed. Continuing with the protected legacy store: \(error.localizedDescription, privacy: .public)"
            )
            return try makeLegacyContainer()
        }
    }

    static func sharedStoreURL() throws -> URL {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw SharedModelContainerError.appGroupUnavailable(
                appGroupIdentifier
            )
        }

        let storeURL = groupURL.appending(
            path: storeRelativePath,
            directoryHint: .notDirectory
        )
        let directoryURL = storeURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw SharedModelContainerError.cannotCreateStoreDirectory(
                directoryURL,
                error
            )
        }

        return storeURL
    }

    private static func makeLegacyContainer() throws -> ModelContainer {
        let schema = Schema([Event.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private static func migrateLegacyEventsIfNeeded(
        to sharedContainer: ModelContainer
    ) throws {
        let legacyContainer = try makeLegacyContainer()
        let legacyContext = ModelContext(legacyContainer)
        let sharedContext = ModelContext(sharedContainer)
        let descriptor = FetchDescriptor<Event>()

        let legacyEvents = try legacyContext.fetch(descriptor)
        guard !legacyEvents.isEmpty else { return }

        let sharedEvents = try sharedContext.fetch(descriptor)
        let sharedEventIDs = Set(sharedEvents.map(\.id))

        for event in legacyEvents where !sharedEventIDs.contains(event.id) {
            sharedContext.insert(event.migrationCopy)
        }

        if sharedContext.hasChanges {
            try sharedContext.save()
        }

        let migratedIDs = Set(
            try sharedContext.fetch(descriptor).map(\.id)
        )
        let legacyIDs = Set(legacyEvents.map(\.id))

        guard legacyIDs.isSubset(of: migratedIDs) else {
            throw SharedModelContainerError.migrationVerificationFailed
        }
    }

    private static func sharedUserDefaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(
            suiteName: appGroupIdentifier
        ) else {
            throw SharedModelContainerError.appGroupDefaultsUnavailable(
                appGroupIdentifier
            )
        }

        return defaults
    }
}

private extension Event {
    var migrationCopy: Event {
        Event(
            id: id,
            title: title,
            isAllDay: isAllDay,
            startDate: startDate,
            endDate: endDate,
            color: color,
            alarmOption: alarmOption,
            alarmTimeIntervalBeforeStart: alarmTimeIntervalBeforeStart,
            alarmCustomValue: alarmCustomValue,
            alarmCustomUnit: alarmCustomUnit,
            repeatUnit: repeatUnit,
            repeatInterval: repeatInterval,
            memo: memo,
            createdAt: createdAt
        )
    }
}

enum SharedModelContainerError: LocalizedError {
    case appGroupUnavailable(String)
    case appGroupDefaultsUnavailable(String)
    case cannotCreateStoreDirectory(URL, Error)
    case migrationVerificationFailed

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let identifier):
            return "App Group container is unavailable: \(identifier)"
        case .appGroupDefaultsUnavailable(let identifier):
            return "App Group UserDefaults is unavailable: \(identifier)"
        case .cannotCreateStoreDirectory(let url, let error):
            return "Cannot create shared store directory at \(url.path): \(error.localizedDescription)"
        case .migrationVerificationFailed:
            return "Legacy Event migration verification failed."
        }
    }
}
