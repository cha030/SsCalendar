import SwiftData

@MainActor
enum WidgetDataStore {
    static func makeModelContainer() throws -> ModelContainer {
        try SharedModelContainer.makeSharedContainer()
    }
}
