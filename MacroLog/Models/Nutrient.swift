import Foundation

/// Unit a nutrient amount is expressed in.
enum NutrientUnit: String, Codable {
    case kilocalories = "kcal"
    case grams = "g"
    case milligrams = "mg"
    case micrograms = "µg"

    var symbol: String { rawValue }
}

/// Broad grouping used to organise nutrients in the UI.
enum NutrientCategory: String, CaseIterable, Identifiable {
    case energy, macronutrient, lipid, mineral, vitamin

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .energy: return String(localized: "nutrient.category.energy")
        case .macronutrient: return String(localized: "nutrient.category.macronutrient")
        case .lipid: return String(localized: "nutrient.category.lipid")
        case .mineral: return String(localized: "nutrient.category.mineral")
        case .vitamin: return String(localized: "nutrient.category.vitamin")
        }
    }
}

/// Every nutrient the app can track. Raw values double as storage keys and
/// as the keys used in the seed database and in AI responses, so they must
/// stay stable.
enum Nutrient: String, CaseIterable, Codable, Identifiable, Hashable {
    case calories
    case protein
    case carbs
    case fat
    case fiber
    case sugar
    case saturatedFat
    case monounsaturatedFat
    case polyunsaturatedFat
    case transFat
    case cholesterol
    case sodium
    case potassium
    case calcium
    case iron
    case magnesium
    case phosphorus
    case zinc
    case selenium
    case copper
    case manganese
    case vitaminA
    case vitaminC
    case vitaminD
    case vitaminE
    case vitaminK
    case thiamin
    case riboflavin
    case niacin
    case vitaminB6
    case folate
    case vitaminB12

    var id: String { rawValue }

    /// The four nutrients the diary tracks against daily targets.
    static let macros: [Nutrient] = [.calories, .protein, .carbs, .fat]

    /// Everything except the headline macros, in display order.
    static let micros: [Nutrient] = allCases.filter { !macros.contains($0) }

    var unit: NutrientUnit {
        switch self {
        case .calories: return .kilocalories
        case .protein, .carbs, .fat, .fiber, .sugar, .saturatedFat,
             .monounsaturatedFat, .polyunsaturatedFat, .transFat:
            return .grams
        case .cholesterol, .sodium, .potassium, .calcium, .iron, .magnesium,
             .phosphorus, .zinc, .copper, .manganese, .vitaminC, .vitaminE,
             .thiamin, .riboflavin, .niacin, .vitaminB6:
            return .milligrams
        case .selenium, .vitaminA, .vitaminD, .vitaminK, .folate, .vitaminB12:
            return .micrograms
        }
    }

    var category: NutrientCategory {
        switch self {
        case .calories: return .energy
        case .protein, .carbs, .fat, .fiber, .sugar: return .macronutrient
        case .saturatedFat, .monounsaturatedFat, .polyunsaturatedFat, .transFat, .cholesterol: return .lipid
        case .sodium, .potassium, .calcium, .iron, .magnesium, .phosphorus, .zinc, .selenium, .copper, .manganese:
            return .mineral
        case .vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminK, .thiamin, .riboflavin, .niacin, .vitaminB6,
             .folate, .vitaminB12:
            return .vitamin
        }
    }

    /// Reference daily intake for an adult, used to show micronutrient
    /// progress. Values follow EU/USDA adult reference values; `nil` means
    /// the nutrient has no meaningful daily target (e.g. sugar).
    var referenceDailyIntake: Double? {
        switch self {
        case .calories, .protein, .carbs, .fat: return nil
        case .fiber: return 30
        case .sugar: return nil
        case .saturatedFat: return 20
        case .monounsaturatedFat, .polyunsaturatedFat: return nil
        case .transFat: return nil
        case .cholesterol: return 300
        case .sodium: return 2300
        case .potassium: return 3500
        case .calcium: return 1000
        case .iron: return 14
        case .magnesium: return 375
        case .phosphorus: return 700
        case .zinc: return 10
        case .selenium: return 55
        case .copper: return 1
        case .manganese: return 2
        case .vitaminA: return 800
        case .vitaminC: return 80
        case .vitaminD: return 20
        case .vitaminE: return 12
        case .vitaminK: return 75
        case .thiamin: return 1.1
        case .riboflavin: return 1.4
        case .niacin: return 16
        case .vitaminB6: return 1.4
        case .folate: return 400
        case .vitaminB12: return 2.5
        }
    }

    /// Nutrients where going over the reference is undesirable.
    var isLimit: Bool {
        switch self {
        case .saturatedFat, .transFat, .cholesterol, .sodium, .sugar: return true
        default: return false
        }
    }

    var localizedName: String {
        String(localized: String.LocalizationValue("nutrient.\(rawValue)"))
    }

    /// Short label for compact UI such as the macro bars.
    var shortName: String {
        switch self {
        case .calories: return String(localized: "kcal")
        case .protein: return String(localized: "nutrient.short.protein")
        case .carbs: return String(localized: "nutrient.short.carbs")
        case .fat: return String(localized: "nutrient.short.fat")
        default: return localizedName
        }
    }

    /// Energy density in kilocalories per gram, for macronutrients only.
    var kilocaloriesPerGram: Double? {
        switch self {
        case .protein, .carbs: return 4
        case .fat: return 9
        default: return nil
        }
    }
}

/// Amounts of nutrients, normally per 100 g of food or per logged portion.
/// Value semantics make it cheap to scale and sum.
struct NutrientProfile: Codable, Equatable {
    private(set) var values: [Nutrient: Double]

    init(_ values: [Nutrient: Double] = [:]) {
        self.values = values.filter { $0.value.isFinite }
    }

    init(calories: Double, protein: Double, carbs: Double, fat: Double) {
        self.init([.calories: calories, .protein: protein, .carbs: carbs, .fat: fat])
    }

    static let empty = NutrientProfile()

    subscript(nutrient: Nutrient) -> Double {
        get { values[nutrient] ?? 0 }
        set { values[nutrient] = newValue }
    }

    var calories: Double { self[.calories] }
    var protein: Double { self[.protein] }
    var carbs: Double { self[.carbs] }
    var fat: Double { self[.fat] }

    func has(_ nutrient: Nutrient) -> Bool { values[nutrient] != nil }

    /// Returns a copy with every amount multiplied by `factor`.
    func scaled(by factor: Double) -> NutrientProfile {
        NutrientProfile(values.mapValues { $0 * factor })
    }

    static func + (lhs: NutrientProfile, rhs: NutrientProfile) -> NutrientProfile {
        var merged = lhs.values
        for (key, value) in rhs.values {
            merged[key, default: 0] += value
        }
        return NutrientProfile(merged)
    }

    static func += (lhs: inout NutrientProfile, rhs: NutrientProfile) {
        lhs = lhs + rhs
    }

    static func sum(_ profiles: [NutrientProfile]) -> NutrientProfile {
        profiles.reduce(.empty, +)
    }

    // MARK: Encoding helpers

    /// Encodes as a flat JSON object keyed by `Nutrient.rawValue`.
    func encoded() -> Data {
        let flat = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        return (try? JSONEncoder().encode(flat)) ?? Data()
    }

    static func decode(_ data: Data?) -> NutrientProfile {
        guard let data, !data.isEmpty,
              let flat = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return .empty
        }
        var values: [Nutrient: Double] = [:]
        for (key, value) in flat {
            if let nutrient = Nutrient(rawValue: key) { values[nutrient] = value }
        }
        return NutrientProfile(values)
    }
}
