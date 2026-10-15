import Foundation
#if !SWIFTDATA_SHIM
import SwiftData
#endif
import Observation

/// Where a food entry came from.
enum FoodSource: String, Codable {
    case seed    // bundled database
    case user    // created by hand
    case ai      // generated from a description or a photo
}

/// One ingredient of a composed dish, stored as a snapshot so the dish stays
/// valid even if the source food is later edited or deleted.
struct DishIngredient: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var grams: Double
    /// Nutrients per 100 g of this ingredient.
    var nutrientsPer100g: NutrientProfile

    var nutrients: NutrientProfile { nutrientsPer100g.scaled(by: grams / 100) }
}

/// A food, either a single ingredient or a composed dish. Nutrient amounts are
/// always stored per 100 g; serving information is kept separately so the UI
/// can offer "1 serving" as a one-tap option.
#if SWIFTDATA_SHIM
@Observable
#else
@Model
#endif
final class FoodItem {
    var id: UUID
    var name: String
    var brand: String?
    /// Translations keyed by ISO language code, JSON encoded. Only seed foods
    /// have them; user-created foods keep the name the user typed.
    var translationsData: Data?
    /// Grams in one serving.
    var servingGrams: Double
    /// Human description of a serving, e.g. "1 slice" or "1 cup".
    var servingLabel: String?
    /// Translations of `servingLabel` keyed by ISO language code, JSON encoded.
    var servingLabelTranslationsData: Data?
    /// Nutrients per 100 g, JSON encoded via `NutrientProfile`.
    var nutrientData: Data
    /// Ingredients when this food is a composed dish, JSON encoded.
    var ingredientsData: Data?
    var sourceRaw: String
    var isFavorite: Bool
    var useCount: Int
    var lastUsedAt: Date?
    var createdAt: Date
    var barcode: String?

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        translations: [String: String] = [:],
        servingGrams: Double = 100,
        servingLabel: String? = nil,
        servingLabelTranslations: [String: String] = [:],
        nutrientsPer100g: NutrientProfile,
        ingredients: [DishIngredient] = [],
        source: FoodSource,
        barcode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.translationsData = translations.isEmpty ? nil : try? JSONEncoder().encode(translations)
        self.servingGrams = servingGrams
        self.servingLabel = servingLabel
        self.servingLabelTranslationsData = servingLabelTranslations.isEmpty ? nil : try? JSONEncoder().encode(servingLabelTranslations)
        self.nutrientData = nutrientsPer100g.encoded()
        self.ingredientsData = ingredients.isEmpty ? nil : try? JSONEncoder().encode(ingredients)
        self.sourceRaw = source.rawValue
        self.isFavorite = false
        self.useCount = 0
        self.lastUsedAt = nil
        self.createdAt = .now
        self.barcode = barcode
    }

    var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .user }
        set { sourceRaw = newValue.rawValue }
    }

    var nutrientsPer100g: NutrientProfile {
        get { NutrientProfile.decode(nutrientData) }
        set { nutrientData = newValue.encoded() }
    }

    var translations: [String: String] {
        get {
            guard let translationsData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: translationsData)) ?? [:]
        }
        set { translationsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var servingLabelTranslations: [String: String] {
        get {
            guard let servingLabelTranslationsData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: servingLabelTranslationsData)) ?? [:]
        }
        set { servingLabelTranslationsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    /// Serving description in the current UI language.
    var displayServingLabel: String? {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return servingLabelTranslations[code] ?? servingLabel
    }

    var ingredients: [DishIngredient] {
        get {
            guard let ingredientsData else { return [] }
            return (try? JSONDecoder().decode([DishIngredient].self, from: ingredientsData)) ?? []
        }
        set { ingredientsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var isDish: Bool { ingredientsData != nil }

    /// Name in the current UI language, falling back to the stored name.
    var displayName: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return translations[code] ?? name
    }

    /// Nutrients in one serving.
    var nutrientsPerServing: NutrientProfile {
        nutrientsPer100g.scaled(by: servingGrams / 100)
    }

    func nutrients(forGrams grams: Double) -> NutrientProfile {
        nutrientsPer100g.scaled(by: grams / 100)
    }

    /// Records a use so the food surfaces in "recent" lists.
    func markUsed(at date: Date = .now) {
        useCount += 1
        lastUsedAt = date
    }

    /// Lower-cased text used by search: every name variant plus the brand.
    var searchText: String {
        ([name, brand ?? ""] + translations.values).joined(separator: " ").lowercased()
    }
}
