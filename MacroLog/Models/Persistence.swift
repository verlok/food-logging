// Persistence layer entry point.
//
// The app uses SwiftData. When compiled with `-D SWIFTDATA_SHIM` (see
// scripts/typecheck.sh) the SwiftData macros are unavailable, so this file
// provides a minimal stand-in API with the same surface. That lets the whole
// code base be type-checked with the bare Swift toolchain, without Xcode.
// The shim is never part of a real build.

import Foundation
import SwiftUI

#if SWIFTDATA_SHIM

/// Stand-in for `SwiftData.PersistentModel`.
protocol PersistentModel: AnyObject, Observable {}

/// Stand-in for `SwiftData.ModelContext`.
final class ModelContext {
    func insert<T: PersistentModel>(_ model: T) {}
    func delete<T: PersistentModel>(_ model: T) {}
    func save() throws {}
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] { [] }
    func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> Int { 0 }
    func delete<T: PersistentModel>(model: T.Type) throws {}
}

/// Stand-in for `SwiftData.ModelContainer`.
final class ModelContainer {
    let mainContext = ModelContext()
    init(for types: any PersistentModel.Type..., configurations: ModelConfiguration...) throws {}
}

/// Stand-in for `SwiftData.ModelConfiguration`.
struct ModelConfiguration {
    init(isStoredInMemoryOnly: Bool = false) {}
}

/// Stand-in for `SwiftData.FetchDescriptor`.
struct FetchDescriptor<T: PersistentModel> {
    var predicate: Predicate<T>?
    var sortBy: [SortDescriptor<T>]
    var fetchLimit: Int?
    init(predicate: Predicate<T>? = nil, sortBy: [SortDescriptor<T>] = []) {
        self.predicate = predicate
        self.sortBy = sortBy
    }
}

/// Stand-in for the `@Query` property wrapper.
@propertyWrapper
struct Query<T: PersistentModel>: DynamicProperty {
    var wrappedValue: [T] { [] }
    init() {}
    init<V: Comparable>(sort: KeyPath<T, V>, order: SortOrder = .forward) {}
    init<V: Comparable>(filter: Predicate<T>?, sort: KeyPath<T, V>, order: SortOrder = .forward) {}
    init(filter: Predicate<T>?) {}
    init(_ descriptor: FetchDescriptor<T>) {}
}

private struct ModelContextKey: EnvironmentKey {
    static let defaultValue = ModelContext()
}

extension EnvironmentValues {
    var modelContext: ModelContext {
        get { self[ModelContextKey.self] }
        set { self[ModelContextKey.self] = newValue }
    }
}

extension View {
    func modelContainer(_ container: ModelContainer) -> some View { self }
}

extension Scene {
    func modelContainer(_ container: ModelContainer) -> some Scene { self }
}

extension FoodItem: PersistentModel, Identifiable {}
extension FoodLogEntry: PersistentModel, Identifiable {}
extension WeightEntry: PersistentModel, Identifiable {}
extension UserProfile: PersistentModel {}

#else

import SwiftData

#endif

/// Builds the app's model container.
enum PersistenceController {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
            return try ModelContainer(
                for: FoodItem.self, FoodLogEntry.self, WeightEntry.self, UserProfile.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to create the model container: \(error)")
        }
    }
}
