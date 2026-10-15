import Foundation
#if !SWIFTDATA_SHIM
import SwiftData
#endif
import Observation
import SwiftUI

/// Single source of truth for the UI. Owns the model context, caches the
/// data the screens need and recomputes expenditure and targets whenever
/// weight or intake changes. All access happens on the main actor.
@MainActor
@Observable
final class AppStore {
    let context: ModelContext

    private(set) var profile: UserProfile
    var selectedDay: Date = Date().startOfDay {
        didSet { reloadDay() }
    }

    private(set) var weights: [WeightEntry] = []
    private(set) var weightSeries: [TrendPoint] = []
    private(set) var expenditure = ExpenditureEstimate(kilocaloriesPerDay: 2000, method: .formula)
    private(set) var targets = DailyTargets(calories: 2000, protein: 120, carbs: 230, fat: 67)
    private(set) var dayEntries: [FoodLogEntry] = []
    private(set) var foods: [FoodItem] = []
    /// Daily calorie totals for the recent past, keyed by start of day.
    private(set) var recentIntake: [Date: NutrientProfile] = [:]

    /// Days of history kept in memory for charts and the estimator.
    static let historyDays = 90

    init(context: ModelContext) {
        self.context = context
        self.profile = Self.loadOrCreateProfile(in: context)
        reloadAll()
    }

    // MARK: - Loading

    private static func loadOrCreateProfile(in context: ModelContext) -> UserProfile {
        if let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }

    func reloadAll() {
        reloadFoods()
        reloadWeights()
        reloadIntake()
        reloadDay()
        recompute()
    }

    func reloadFoods() {
        let descriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)])
        foods = (try? context.fetch(descriptor)) ?? []
    }

    private func reloadWeights() {
        let descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.day)])
        weights = (try? context.fetch(descriptor)) ?? []
        weightSeries = WeightTrend.series(from: weights.map { ($0.day, $0.weightKg) })
    }

    private func reloadIntake() {
        let start = Date().startOfDay.adding(days: -Self.historyDays)
        let entries = Repository.entries(since: start, in: context)
        var totals: [Date: NutrientProfile] = [:]
        for entry in entries {
            totals[entry.day, default: .empty] += entry.nutrients
        }
        recentIntake = totals
    }

    private func reloadDay() {
        dayEntries = Repository.entries(on: selectedDay, in: context).sorted { $0.time < $1.time }
    }

    /// Recomputes expenditure and targets from the cached data.
    func recompute() {
        let intake = recentIntake.map { IntakeDay(day: $0.key, calories: $0.value.calories) }
        expenditure = ExpenditureEstimator.estimate(
            body: profile.bodySpec,
            goal: profile.goalSpec,
            weightSeries: weightSeries,
            intake: intake
        )
        targets = TargetCalculator.targets(
            body: profile.bodySpec,
            goal: profile.goalSpec,
            expenditure: expenditure.kilocaloriesPerDay,
            weightKg: currentWeightKg ?? 70
        )
    }

    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("Save failed: \(error)")
        }
    }

    // MARK: - Profile

    /// Call after editing the profile so dependent values refresh.
    func profileDidChange() {
        save()
        recompute()
    }

    func completeOnboarding(startWeightKg: Double?) {
        if let startWeightKg { logWeight(startWeightKg, on: .now) }
        profile.onboardingCompleted = true
        profileDidChange()
    }

    // MARK: - Weight

    /// Latest trend weight, or the latest measurement when the trend is
    /// not available yet.
    var currentWeightKg: Double? {
        weightSeries.last?.trendKg ?? weights.last?.weightKg
    }

    var latestMeasurementKg: Double? { weights.last?.weightKg }

    func logWeight(_ kg: Double, on date: Date) {
        let day = date.startOfDay
        if let existing = weights.first(where: { $0.day == day }) {
            existing.weightKg = kg
        } else {
            context.insert(WeightEntry(day: day, weightKg: kg))
        }
        save()
        reloadWeights()
        recompute()
    }

    func deleteWeight(_ entry: WeightEntry) {
        context.delete(entry)
        save()
        reloadWeights()
        recompute()
    }

    /// Trend change over the last `days` days, if enough history exists.
    func trendChange(overDays days: Int) -> Double? {
        guard let last = weightSeries.last else { return nil }
        let startDay = last.day.adding(days: -days)
        guard let start = WeightTrend.trend(on: startDay, in: weightSeries),
              weightSeries.first.map({ $0.day <= startDay }) == true else { return nil }
        return last.trendKg - start
    }

    // MARK: - Diary

    var dayTotals: NutrientProfile {
        NutrientProfile.sum(dayEntries.map(\.nutrients))
    }

    func totals(on day: Date) -> NutrientProfile {
        if day.startOfDay == selectedDay { return dayTotals }
        return recentIntake[day.startOfDay] ?? .empty
    }

    /// The moment pre-selected for a new entry on the selected day.
    var suggestedLogTime: Date {
        Date.suggestedLogTime(on: selectedDay)
    }

    func log(_ food: FoodItem, grams: Double, at time: Date) {
        let entry = FoodLogEntry(time: time, food: food, grams: grams)
        context.insert(entry)
        food.markUsed()
        save()
        didChangeDiary()
    }

    func quickAdd(name: String, nutrients: NutrientProfile, at time: Date) {
        let entry = FoodLogEntry(time: time, name: name, nutrients: nutrients)
        context.insert(entry)
        save()
        didChangeDiary()
    }

    func update(_ entry: FoodLogEntry, grams: Double, time: Date) {
        entry.grams = grams
        entry.setTime(time)
        save()
        didChangeDiary()
    }

    /// Moves an entry to another day and/or time.
    func move(_ entry: FoodLogEntry, to time: Date) {
        entry.setTime(time)
        save()
        didChangeDiary()
    }

    /// Duplicates an entry at another day and/or time.
    func copy(_ entry: FoodLogEntry, to time: Date) {
        context.insert(entry.copy(to: time))
        save()
        didChangeDiary()
    }

    /// Copies every entry of `sourceDay` into `targetDay`, keeping the
    /// clock times. Returns how many entries were copied.
    @discardableResult
    func copyEntries(from sourceDay: Date, to targetDay: Date) -> Int {
        let source = Repository.entries(on: sourceDay, in: context)
        for entry in source {
            context.insert(entry.copy(to: Date.combine(day: targetDay, time: entry.time)))
        }
        save()
        didChangeDiary()
        return source.count
    }

    func delete(_ entry: FoodLogEntry) {
        context.delete(entry)
        save()
        didChangeDiary()
    }

    private func didChangeDiary() {
        reloadIntake()
        reloadDay()
        recompute()
    }

    // MARK: - Foods

    func insert(_ food: FoodItem) {
        context.insert(food)
        save()
        reloadFoods()
    }

    func foodDidChange() {
        save()
        reloadFoods()
    }

    func delete(_ food: FoodItem) {
        context.delete(food)
        save()
        reloadFoods()
    }

    func toggleFavorite(_ food: FoodItem) {
        food.isFavorite.toggle()
        save()
    }

    func food(withID id: UUID?) -> FoodItem? {
        guard let id else { return nil }
        return foods.first { $0.id == id }
    }

    var recentFoods: [FoodItem] {
        foods.filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
    }

    var favoriteFoods: [FoodItem] {
        foods.filter(\.isFavorite).sorted { $0.displayName < $1.displayName }
    }

    var customFoods: [FoodItem] {
        foods.filter { $0.source != .seed }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Case- and diacritic-insensitive search; every word must match.
    func search(_ query: String) -> [FoodItem] {
        let words = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(separator: " ")
            .map(String.init)
        guard !words.isEmpty else { return foods }
        return foods
            .filter { food in
                let haystack = food.searchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                return words.allSatisfy { haystack.contains($0) }
            }
            .sorted { lhs, rhs in
                // Prefer foods used before, then shorter (more exact) names.
                if (lhs.lastUsedAt != nil) != (rhs.lastUsedAt != nil) { return lhs.lastUsedAt != nil }
                return lhs.displayName.count < rhs.displayName.count
            }
    }

    // MARK: - History for charts

    /// Per-day totals for the last `days` days ending today, including
    /// days without entries (as empty profiles).
    func dailyTotals(lastDays days: Int) -> [(day: Date, totals: NutrientProfile)] {
        let today = Date().startOfDay
        return (0..<days).reversed().map { offset in
            let day = today.adding(days: -offset)
            return (day, totals(on: day))
        }
    }
}

/// The few queries that need store-level filtering. Kept apart so the
/// predicate macros are isolated from the rest of the code.
enum Repository {
    @MainActor
    static func entries(on day: Date, in context: ModelContext) -> [FoodLogEntry] {
        let start = day.startOfDay
        #if SWIFTDATA_SHIM
        let all = (try? context.fetch(FetchDescriptor<FoodLogEntry>())) ?? []
        return all.filter { $0.day == start }
        #else
        let descriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day == start },
            sortBy: [SortDescriptor(\.time)]
        )
        return (try? context.fetch(descriptor)) ?? []
        #endif
    }

    @MainActor
    static func entries(since start: Date, in context: ModelContext) -> [FoodLogEntry] {
        #if SWIFTDATA_SHIM
        let all = (try? context.fetch(FetchDescriptor<FoodLogEntry>())) ?? []
        return all.filter { $0.day >= start }
        #else
        let descriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day >= start }
        )
        return (try? context.fetch(descriptor)) ?? []
        #endif
    }
}
