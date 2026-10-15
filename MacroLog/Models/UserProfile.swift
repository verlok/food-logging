import Foundation
#if !SWIFTDATA_SHIM
import SwiftData
#endif
import Observation

enum BiologicalSex: String, CaseIterable, Codable, Identifiable {
    case female, male

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .female: return String(localized: "sex.female")
        case .male: return String(localized: "sex.male")
        }
    }
}

/// Physical activity level, used only for the initial expenditure estimate
/// before enough weight and intake data exist.
enum ActivityLevel: String, CaseIterable, Codable, Identifiable {
    case sedentary, light, moderate, active, veryActive

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }

    var localizedName: String {
        switch self {
        case .sedentary: return String(localized: "activity.sedentary")
        case .light: return String(localized: "activity.light")
        case .moderate: return String(localized: "activity.moderate")
        case .active: return String(localized: "activity.active")
        case .veryActive: return String(localized: "activity.veryActive")
        }
    }

    var localizedDescription: String {
        switch self {
        case .sedentary: return String(localized: "activity.sedentary.description")
        case .light: return String(localized: "activity.light.description")
        case .moderate: return String(localized: "activity.moderate.description")
        case .active: return String(localized: "activity.active.description")
        case .veryActive: return String(localized: "activity.veryActive.description")
        }
    }
}

enum GoalType: String, CaseIterable, Codable, Identifiable {
    case lose, maintain, gain

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .lose: return String(localized: "goal.lose")
        case .maintain: return String(localized: "goal.maintain")
        case .gain: return String(localized: "goal.gain")
        }
    }

    var systemImage: String {
        switch self {
        case .lose: return "arrow.down.right"
        case .maintain: return "equal"
        case .gain: return "arrow.up.right"
        }
    }
}

/// How the calorie target is split into macronutrients.
enum MacroStrategy: String, CaseIterable, Codable, Identifiable {
    case balanced, lowCarb, highProtein, custom

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .balanced: return String(localized: "strategy.balanced")
        case .lowCarb: return String(localized: "strategy.lowCarb")
        case .highProtein: return String(localized: "strategy.highProtein")
        case .custom: return String(localized: "strategy.custom")
        }
    }

    /// Protein in grams per kilogram of body weight.
    var proteinGramsPerKg: Double {
        switch self {
        case .balanced: return 1.6
        case .lowCarb: return 1.8
        case .highProtein: return 2.2
        case .custom: return 1.8
        }
    }

    /// Share of calories coming from fat.
    var fatFraction: Double {
        switch self {
        case .balanced: return 0.30
        case .lowCarb: return 0.45
        case .highProtein: return 0.28
        case .custom: return 0.30
        }
    }
}

/// The single user of the app and their goal settings.
#if SWIFTDATA_SHIM
@Observable
#else
@Model
#endif
final class UserProfile {
    var sexRaw: String
    var birthDate: Date
    var heightCm: Double
    var activityRaw: String
    var goalRaw: String
    /// Desired weekly change in kilograms (always positive; the goal decides
    /// the direction).
    var weeklyRateKg: Double
    var strategyRaw: String
    var customProteinGramsPerKg: Double
    var customFatFraction: Double
    /// Optional manual override of the daily expenditure.
    var manualExpenditure: Double?
    var onboardingCompleted: Bool
    var createdAt: Date

    init(
        sex: BiologicalSex = .male,
        birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now,
        heightCm: Double = 175,
        activity: ActivityLevel = .light,
        goal: GoalType = .maintain,
        weeklyRateKg: Double = 0.5,
        strategy: MacroStrategy = .balanced
    ) {
        self.sexRaw = sex.rawValue
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.activityRaw = activity.rawValue
        self.goalRaw = goal.rawValue
        self.weeklyRateKg = weeklyRateKg
        self.strategyRaw = strategy.rawValue
        self.customProteinGramsPerKg = 1.8
        self.customFatFraction = 0.30
        self.manualExpenditure = nil
        self.onboardingCompleted = false
        self.createdAt = .now
    }

    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .light }
        set { activityRaw = newValue.rawValue }
    }

    var goal: GoalType {
        get { GoalType(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }

    var strategy: MacroStrategy {
        get { MacroStrategy(rawValue: strategyRaw) ?? .balanced }
        set { strategyRaw = newValue.rawValue }
    }

    var proteinGramsPerKg: Double {
        strategy == .custom ? customProteinGramsPerKg : strategy.proteinGramsPerKg
    }

    var fatFraction: Double {
        strategy == .custom ? customFatFraction : strategy.fatFraction
    }

    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 30
    }

    /// Plain-value snapshot used by the nutrition engine, which must not
    /// depend on the persistence layer.
    var bodySpec: BodySpec {
        BodySpec(sex: sex, ageYears: ageYears, heightCm: heightCm, activity: activity)
    }

    var goalSpec: GoalSpec {
        GoalSpec(
            goal: goal,
            weeklyRateKg: weeklyRateKg,
            proteinGramsPerKg: proteinGramsPerKg,
            fatFraction: fatFraction,
            manualExpenditure: manualExpenditure
        )
    }
}
