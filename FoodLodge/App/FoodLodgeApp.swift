import SwiftUI
#if !SWIFTDATA_SHIM
import SwiftData
#endif

@main
struct FoodLodgeApp: App {
    private let container: ModelContainer
    @State private var store: AppStore

    init() {
        let container = PersistenceController.makeContainer()
        self.container = container
        FoodSeeder.seedIfNeeded(context: container.mainContext)
        _store = State(initialValue: AppStore(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(container)
    }
}
