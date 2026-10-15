import Foundation

// Pure-value nutrition maths. Nothing in this file touches persistence, so it
// can be unit tested and reused without SwiftData.

/// Energy stored in one kilogram of body mass, used to translate weight
/// change into calories. 7700 kcal/kg is the standard working figure.
let kilocaloriesPerKilogram: Double = 7700

struct BodySpec: Equatable {
    var sex: BiologicalSex
    var ageYears: Int
    var heightCm: Double
    var activity: ActivityLevel
}

struct GoalSpec: Equatable {
    var goal: GoalType
    var weeklyRateKg: Double
    var proteinGramsPerKg: Double
    var fatFraction: Double
    var manualExpenditure: Double?
}

/// A day's weight, the smoothed trend and whether it was measured or carried
/// forward from a previous day.
struct TrendPoint: Identifiable, Equatable {
    var day: Date
    var weightKg: Double?
    var trendKg: Double

    var id: Date { day }
}

/// A day of logged intake summarised for the expenditure estimator.
struct IntakeDay: Equatable {
    var day: Date
    var calories: Double
}

enum WeightTrend {
    /// Smoothing factor of the exponential moving average. 0.1 reacts over
    /// roughly two weeks, which filters water fluctuations without lagging
    /// real change too much.
    static let alpha = 0.1

    /// Builds a daily series from sparse measurements. Days without a
    /// measurement keep the previous trend value.
    static func series(
        from entries: [(day: Date, weightKg: Double)],
        calendar: Calendar = .current
    ) -> [TrendPoint] {
        let sorted = entries.sorted { $0.day < $1.day }
        guard let first = sorted.first, let last = sorted.last else { return [] }
        var byDay: [Date: Double] = [:]
        for entry in sorted {
            byDay[calendar.startOfDay(for: entry.day)] = entry.weightKg
        }

        var points: [TrendPoint] = []
        var trend = first.weightKg
        var day = calendar.startOfDay(for: first.day)
        let end = calendar.startOfDay(for: last.day)
        while day <= end {
            if let weight = byDay[day] {
                if points.isEmpty {
                    trend = weight
                } else {
                    trend += alpha * (weight - trend)
                }
                points.append(TrendPoint(day: day, weightKg: weight, trendKg: trend))
            } else {
                points.append(TrendPoint(day: day, weightKg: nil, trendKg: trend))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    /// Trend value on or before `day`, if any measurement exists by then.
    static func trend(on day: Date, in series: [TrendPoint]) -> Double? {
        series.last { $0.day <= day }?.trendKg
    }
}

enum ExpenditureMethod: Equatable {
    /// Formula only: not enough data yet.
    case formula
    /// Mix of formula and observed energy balance; `dataWeight` is the share
    /// of the observed estimate (0...1).
    case adaptive(dataWeight: Double, loggedDays: Int)
    /// User typed a value in settings.
    case manual
}

struct ExpenditureEstimate: Equatable {
    var kilocaloriesPerDay: Double
    var method: ExpenditureMethod
}

enum ExpenditureEstimator {
    /// Days of history examined when estimating energy balance.
    static let window = 28
    /// A logged day with fewer calories than this is treated as incomplete
    /// and ignored, so forgotten days do not drag the estimate down.
    static let minimumCompleteDayCalories: Double = 800
    /// Logged days needed before observed data starts to count.
    static let minimumLoggedDays = 7
    /// Logged days at which observed data reaches full weight.
    static let fullConfidenceDays = 21

    /// Mifflin-St Jeor resting metabolic rate.
    static func restingMetabolicRate(body: BodySpec, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * body.heightCm - 5 * Double(body.ageYears)
        return body.sex == .male ? base + 5 : base - 161
    }

    static func formulaExpenditure(body: BodySpec, weightKg: Double) -> Double {
        restingMetabolicRate(body: body, weightKg: weightKg) * body.activity.multiplier
    }

    /// Estimates daily energy expenditure from the weight trend and the
    /// calories logged over the last `window` days, blended with the formula
    /// estimate according to how much data exists.
    static func estimate(
        body: BodySpec,
        goal: GoalSpec,
        weightSeries: [TrendPoint],
        intake: [IntakeDay],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> ExpenditureEstimate {
        let currentWeight = weightSeries.last?.trendKg ?? weightSeries.last?.weightKg ?? 70
        let formula = formulaExpenditure(body: body, weightKg: currentWeight)

        if let manual = goal.manualExpenditure, manual > 0 {
            return ExpenditureEstimate(kilocaloriesPerDay: manual, method: .manual)
        }

        let end = calendar.startOfDay(for: today)
        guard let start = calendar.date(byAdding: .day, value: -window, to: end) else {
            return ExpenditureEstimate(kilocaloriesPerDay: formula, method: .formula)
        }

        // Only days strictly before today count: today is still being logged.
        let completeDays = intake
            .filter { $0.day >= start && $0.day < end && $0.calories >= minimumCompleteDayCalories }
            .sorted { $0.day < $1.day }

        guard completeDays.count >= minimumLoggedDays,
              let firstDay = completeDays.first?.day,
              let lastDay = completeDays.last?.day,
              let startTrend = WeightTrend.trend(on: firstDay, in: weightSeries),
              let endTrend = WeightTrend.trend(on: lastDay, in: weightSeries),
              let span = calendar.dateComponents([.day], from: firstDay, to: lastDay).day,
              span >= 6
        else {
            return ExpenditureEstimate(kilocaloriesPerDay: formula, method: .formula)
        }

        let averageIntake = completeDays.map(\.calories).reduce(0, +) / Double(completeDays.count)
        let dailyBalance = (endTrend - startTrend) * kilocaloriesPerKilogram / Double(span)
        var observed = averageIntake - dailyBalance
        // Guard against wild swings from incomplete logging.
        observed = min(max(observed, formula * 0.6), formula * 1.6)

        let progress = Double(completeDays.count - minimumLoggedDays)
            / Double(fullConfidenceDays - minimumLoggedDays)
        let dataWeight = min(max(progress, 0), 1) * 0.85
        let blended = formula * (1 - dataWeight) + observed * dataWeight
        return ExpenditureEstimate(
            kilocaloriesPerDay: blended,
            method: .adaptive(dataWeight: dataWeight, loggedDays: completeDays.count)
        )
    }
}

/// Daily nutrition targets derived from expenditure and goal.
struct DailyTargets: Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    func target(for nutrient: Nutrient) -> Double? {
        switch nutrient {
        case .calories: return calories
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        default: return nutrient.referenceDailyIntake
        }
    }
}

enum TargetCalculator {
    /// Safety floors below which the app will not push the calorie target.
    static func minimumCalories(for sex: BiologicalSex) -> Double {
        sex == .male ? 1500 : 1200
    }

    static func targets(
        body: BodySpec,
        goal: GoalSpec,
        expenditure: Double,
        weightKg: Double
    ) -> DailyTargets {
        let dailyDelta = goal.weeklyRateKg * kilocaloriesPerKilogram / 7
        var calories: Double
        switch goal.goal {
        case .lose: calories = expenditure - dailyDelta
        case .maintain: calories = expenditure
        case .gain: calories = expenditure + dailyDelta
        }
        calories = max(calories, minimumCalories(for: body.sex))
        calories = (calories / 10).rounded() * 10

        var protein = goal.proteinGramsPerKg * weightKg
        var fat = calories * goal.fatFraction / 9
        var carbs = (calories - protein * 4 - fat * 9) / 4

        // Keep at least a modest carbohydrate allowance when the deficit is
        // deep: trim fat first, then protein.
        let minimumCarbs = 50.0
        if carbs < minimumCarbs {
            let shortfall = (minimumCarbs - carbs) * 4
            let fatReduction = min(shortfall / 9, fat * 0.4)
            fat -= fatReduction
            carbs = (calories - protein * 4 - fat * 9) / 4
            if carbs < minimumCarbs {
                protein = max(protein - (minimumCarbs - carbs) * 4 / 4, weightKg * 1.2)
                carbs = (calories - protein * 4 - fat * 9) / 4
            }
        }
        carbs = max(carbs, 0)

        return DailyTargets(
            calories: calories,
            protein: protein.rounded(),
            carbs: carbs.rounded(),
            fat: fat.rounded()
        )
    }
}
