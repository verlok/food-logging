import XCTest
@testable import MacroLog

final class NutritionEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var day0: Date { calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: day0)! }

    private let body = BodySpec(sex: .male, ageYears: 35, heightCm: 178, activity: .light)

    func testRestingMetabolicRateMatchesMifflinStJeor() {
        let rmr = ExpenditureEstimator.restingMetabolicRate(body: body, weightKg: 80)
        let expectedMale: Double = 800 + 1112.5 - 175 + 5
        XCTAssertEqual(rmr, expectedMale, accuracy: 0.01)
        let female = BodySpec(sex: .female, ageYears: 35, heightCm: 165, activity: .light)
        let expectedFemale: Double = 600 + 1031.25 - 175 - 161
        XCTAssertEqual(ExpenditureEstimator.restingMetabolicRate(body: female, weightKg: 60), expectedFemale, accuracy: 0.01)
    }

    func testWeightTrendSmoothsAndFillsGaps() {
        let series = WeightTrend.series(from: [(day(0), 80), (day(1), 81), (day(3), 79)], calendar: calendar)
        XCTAssertEqual(series.count, 4)
        XCTAssertEqual(series[0].trendKg, 80)
        XCTAssertEqual(series[1].trendKg, 80.1, accuracy: 0.0001)
        XCTAssertNil(series[2].weightKg)
        XCTAssertEqual(series[2].trendKg, 80.1, accuracy: 0.0001)
        let expectedThird: Double = 80.1 + 0.1 * (79 - 80.1)
        XCTAssertEqual(series[3].trendKg, expectedThird, accuracy: 0.0001)
    }

    func testExpenditureFallsBackToFormulaWithoutData() {
        let goal = GoalSpec(goal: .maintain, weeklyRateKg: 0, proteinGramsPerKg: 1.8, fatFraction: 0.3, manualExpenditure: nil)
        let estimate = ExpenditureEstimator.estimate(body: body, goal: goal, weightSeries: [], intake: [], today: day(10), calendar: calendar)
        XCTAssertEqual(estimate.method, .formula)
    }

    func testExpenditureAdaptsToStableWeightAndIntake() {
        // Weight perfectly stable while eating 2600 kcal/day for three weeks:
        // the observed expenditure is 2600 and the blend moves towards it.
        let weights = (0..<22).map { (day($0), 80.0) }
        let intake = (0..<21).map { IntakeDay(day: day($0), calories: 2600) }
        let goal = GoalSpec(goal: .maintain, weeklyRateKg: 0, proteinGramsPerKg: 1.8, fatFraction: 0.3, manualExpenditure: nil)
        let series = WeightTrend.series(from: weights, calendar: calendar)
        let estimate = ExpenditureEstimator.estimate(body: body, goal: goal, weightSeries: series, intake: intake, today: day(21), calendar: calendar)
        let formula = ExpenditureEstimator.formulaExpenditure(body: body, weightKg: 80)
        guard case .adaptive(let weight, let days) = estimate.method else { return XCTFail("expected adaptive") }
        XCTAssertEqual(days, 21)
        XCTAssertEqual(weight, 0.85, accuracy: 0.001)
        let expected: Double = formula * 0.15 + 2600 * 0.85
        XCTAssertEqual(estimate.kilocaloriesPerDay, expected, accuracy: 0.5)
    }

    func testExpenditureAccountsForWeightLoss() {
        // Losing 0.5 kg over 20 days on 2000 kcal/day implies roughly
        // 2000 + 0.5 * 7700 / 20 = 2192 kcal/day observed.
        let weights = (0..<21).map { (day($0), 80.0 - 0.5 * Double($0) / 20) }
        var series = WeightTrend.series(from: weights, calendar: calendar)
        // Use the raw weights as the trend to make the expectation exact.
        series = series.map { TrendPoint(day: $0.day, weightKg: $0.weightKg, trendKg: $0.weightKg ?? $0.trendKg) }
        let intake = (0..<21).map { IntakeDay(day: day($0), calories: 2000) }
        let goal = GoalSpec(goal: .lose, weeklyRateKg: 0.5, proteinGramsPerKg: 1.8, fatFraction: 0.3, manualExpenditure: nil)
        let estimate = ExpenditureEstimator.estimate(body: body, goal: goal, weightSeries: series, intake: intake, today: day(21), calendar: calendar)
        let formula = ExpenditureEstimator.formulaExpenditure(body: body, weightKg: 79.5)
        let observed = 2000 + 0.5 * kilocaloriesPerKilogram / 20
        let expected: Double = formula * 0.15 + observed * 0.85
        XCTAssertEqual(estimate.kilocaloriesPerDay, expected, accuracy: 1)
    }

    func testIncompleteDaysAreIgnored() {
        let weights = (0..<22).map { (day($0), 80.0) }
        var intake = (0..<21).map { IntakeDay(day: day($0), calories: 2600) }
        intake[3] = IntakeDay(day: day(3), calories: 300) // forgot to log
        let goal = GoalSpec(goal: .maintain, weeklyRateKg: 0, proteinGramsPerKg: 1.8, fatFraction: 0.3, manualExpenditure: nil)
        let series = WeightTrend.series(from: weights, calendar: calendar)
        let estimate = ExpenditureEstimator.estimate(body: body, goal: goal, weightSeries: series, intake: intake, today: day(21), calendar: calendar)
        guard case .adaptive(_, let days) = estimate.method else { return XCTFail("expected adaptive") }
        XCTAssertEqual(days, 20)
    }

    func testManualExpenditureWins() {
        let goal = GoalSpec(goal: .maintain, weeklyRateKg: 0, proteinGramsPerKg: 1.8, fatFraction: 0.3, manualExpenditure: 2345)
        let estimate = ExpenditureEstimator.estimate(body: body, goal: goal, weightSeries: [], intake: [], today: day(0), calendar: calendar)
        XCTAssertEqual(estimate.kilocaloriesPerDay, 2345)
        XCTAssertEqual(estimate.method, .manual)
    }

    func testTargetsForWeightLoss() {
        let goal = GoalSpec(goal: .lose, weeklyRateKg: 0.5, proteinGramsPerKg: 2.0, fatFraction: 0.3, manualExpenditure: nil)
        let targets = TargetCalculator.targets(body: body, goal: goal, expenditure: 2600, weightKg: 80)
        XCTAssertEqual(targets.calories, 2050, accuracy: 0.01) // 2600 - 550
        XCTAssertEqual(targets.protein, 160)
        let expectedFat: Double = (2050 * 0.3 / 9).rounded()
        XCTAssertEqual(targets.fat, expectedFat)
        let expectedCarbs: Double = ((2050 - 640 - 615) / 4).rounded()
        XCTAssertEqual(targets.carbs, expectedCarbs, accuracy: 1)
    }

    func testTargetsRespectCalorieFloor() {
        let goal = GoalSpec(goal: .lose, weeklyRateKg: 1.0, proteinGramsPerKg: 1.8, fatFraction: 0.3, manualExpenditure: nil)
        let female = BodySpec(sex: .female, ageYears: 40, heightCm: 160, activity: .sedentary)
        let targets = TargetCalculator.targets(body: female, goal: goal, expenditure: 1600, weightKg: 55)
        XCTAssertEqual(targets.calories, 1200)
        XCTAssertGreaterThanOrEqual(targets.carbs, 50)
    }

    func testNutrientProfileScalingAndSum() {
        let per100 = NutrientProfile(calories: 100, protein: 10, carbs: 5, fat: 2)
        let portion = per100.scaled(by: 1.5)
        XCTAssertEqual(portion.calories, 150)
        let total = NutrientProfile.sum([portion, per100])
        XCTAssertEqual(total.protein, 25)
        let decoded = NutrientProfile.decode(total.encoded())
        XCTAssertEqual(decoded, total)
    }

    func testSeedDatabaseLoadsAndIsConsistent() throws {
        let foods = try FoodSeeder.loadSeedFoods()
        XCTAssertGreaterThan(foods.count, 100)
        for food in foods {
            XCTAssertNotNil(food.names["en"], food.id)
            XCTAssertNotNil(food.names["it"], food.id)
            let item = FoodSeeder.makeFoodItem(from: food)
            XCTAssertGreaterThan(item.nutrientsPer100g.calories, 0, food.id)
            // Macro-derived energy should be within a sane margin of the
            // stated calories (alcohol and fibre explain the rest).
            let macros = item.nutrientsPer100g
            let derived = macros.protein * 4 + macros.carbs * 4 + macros.fat * 9
            if derived > 50 {
                let tolerance: Double = macros.calories * 0.25 + 15
                XCTAssertEqual(derived, macros.calories, accuracy: tolerance, food.id)
            }
        }
        XCTAssertEqual(Set(foods.map(\.id)).count, foods.count)
    }

    func testStableUUIDIsDeterministic() {
        XCTAssertEqual(FoodSeeder.stableUUIDString(for: "apple"), FoodSeeder.stableUUIDString(for: "apple"))
        XCTAssertNotEqual(FoodSeeder.stableUUIDString(for: "apple"), FoodSeeder.stableUUIDString(for: "pear"))
        XCTAssertNotNil(UUID(uuidString: FoodSeeder.stableUUIDString(for: "apple")))
    }

    func testSuggestedLogTimeKeepsClockOnOtherDays() {
        var components = DateComponents(year: 2026, month: 1, day: 10, hour: 13, minute: 30)
        let now = calendar.date(from: components)!
        XCTAssertEqual(Date.suggestedLogTime(on: now, now: now), now)
        components.day = 3
        let otherDay = calendar.date(from: components)!
        let suggested = Date.suggestedLogTime(on: otherDay, now: now)
        XCTAssertTrue(Calendar.current.isDate(suggested, inSameDayAs: otherDay))
        XCTAssertEqual(Calendar.current.component(.hour, from: suggested), 13)
        XCTAssertEqual(Calendar.current.component(.minute, from: suggested), 30)
    }

    func testEntryCopyKeepsContentAtNewTime() {
        let food = FoodItem(name: "Test", servingGrams: 50, nutrientsPer100g: NutrientProfile(calories: 200, protein: 10, carbs: 20, fat: 5), source: .user)
        let entry = FoodLogEntry(time: day(1), food: food, grams: 75)
        let copy = entry.copy(to: day(4))
        XCTAssertEqual(copy.grams, 75)
        XCTAssertEqual(copy.foodID, food.id)
        XCTAssertEqual(copy.nutrients.calories, 150, accuracy: 0.001)
        XCTAssertEqual(copy.day, day(4))
        XCTAssertNotEqual(copy.id, entry.id)
    }
}
