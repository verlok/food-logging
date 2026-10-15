import Foundation
#if !SWIFTDATA_SHIM
import SwiftData
#endif

/// Shape of one record in `foods_seed.json`.
struct SeedFood: Decodable {
    var id: String
    var names: [String: String]
    var serving: Double
    var servingLabel: [String: String]?
    var nutrients: [String: Double]
}

/// Loads the bundled food database into the store on first launch.
enum FoodSeeder {
    static let seededVersionKey = "foods.seed.version"
    static let currentVersion = 1

    static func loadSeedFoods() throws -> [SeedFood] {
        guard let url = Bundle.main.url(forResource: "foods_seed", withExtension: "json") else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([SeedFood].self, from: data)
    }

    static func makeFoodItem(from seed: SeedFood) -> FoodItem {
        var values: [Nutrient: Double] = [:]
        for (key, value) in seed.nutrients {
            if let nutrient = Nutrient(rawValue: key) { values[nutrient] = value }
        }
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let name = seed.names[code] ?? seed.names["en"] ?? seed.id
        let label = seed.servingLabel?[code] ?? seed.servingLabel?["en"]
        // Seed identifiers are stable, so derive the UUID from them to keep
        // log entries linked across reinstalls.
        let uuid = UUID(uuidString: stableUUIDString(for: seed.id)) ?? UUID()
        return FoodItem(
            id: uuid,
            name: name,
            translations: seed.names,
            servingGrams: seed.serving,
            servingLabel: label,
            servingLabelTranslations: seed.servingLabel ?? [:],
            nutrientsPer100g: NutrientProfile(values),
            source: .seed
        )
    }

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: seededVersionKey) < currentVersion else { return }
        do {
            let existing = try context.fetchCount(FetchDescriptor<FoodItem>())
            if existing == 0 {
                for seed in try loadSeedFoods() {
                    context.insert(makeFoodItem(from: seed))
                }
                try context.save()
            }
            defaults.set(currentVersion, forKey: seededVersionKey)
        } catch {
            assertionFailure("Seeding failed: \(error)")
        }
    }

    /// Deterministic UUID-shaped string from a seed id (FNV-1a based). Not
    /// cryptographic; it only needs to be stable and unique per id.
    static func stableUUIDString(for id: String) -> String {
        var hash1: UInt64 = 0xcbf29ce484222325
        var hash2: UInt64 = 0x84222325cbf29ce4
        for byte in id.utf8 {
            hash1 = (hash1 ^ UInt64(byte)) &* 0x100000001b3
            hash2 = (hash2 &+ UInt64(byte)) &* 0x100000001b3
        }
        let hex = String(format: "%016llx%016llx", hash1, hash2)
        let chars = Array(hex)
        return "\(String(chars[0..<8]))-\(String(chars[8..<12]))-\(String(chars[12..<16]))-\(String(chars[16..<20]))-\(String(chars[20..<32]))"
    }
}
