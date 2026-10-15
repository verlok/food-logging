import SwiftUI
import Charts

/// Trends: weight, calories against target, macro split, and average
/// micronutrient coverage.
struct ChartsView: View {
    @Environment(AppStore.self) private var store
    @State private var range: ChartRange = .month

    private var days: Int { min(range.days, AppStore.historyDays) }
    private var history: [(day: Date, totals: NutrientProfile)] { store.dailyTotals(lastDays: days) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Range", selection: $range) {
                        ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    section("Weight") {
                        WeightChart(series: store.weightSeries, days: days)
                            .frame(height: 200)
                    }
                    section("Calories") {
                        CaloriesChart(history: history, target: store.targets.calories, expenditure: store.expenditure.kilocaloriesPerDay)
                            .frame(height: 200)
                        caloriesLegend
                    }
                    section("Macronutrients") {
                        MacrosChart(history: history)
                            .frame(height: 200)
                        macroAverages
                    }
                    section("Micronutrients") {
                        MicronutrientCoverage(history: history)
                    }
                }
                .padding()
            }
            .navigationTitle("Charts")
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .card()
    }

    private var loggedDays: [(day: Date, totals: NutrientProfile)] {
        history.filter { $0.totals.calories > 0 }
    }

    private var caloriesLegend: some View {
        let average = loggedDays.isEmpty ? 0 : loggedDays.map(\.totals.calories).reduce(0, +) / Double(loggedDays.count)
        return HStack {
            legend("Average eaten", value: "\(Format.kcal(average)) kcal", color: Nutrient.calories.tint)
            Spacer()
            legend("Target", value: "\(Format.kcal(store.targets.calories)) kcal", color: .green)
            Spacer()
            legend("Expenditure", value: "\(Format.kcal(store.expenditure.kilocaloriesPerDay)) kcal", color: .secondary)
        }
        .font(.caption)
    }

    private var macroAverages: some View {
        let count = Double(max(loggedDays.count, 1))
        let sum = NutrientProfile.sum(loggedDays.map(\.totals))
        return HStack {
            ForEach([Nutrient.protein, .carbs, .fat]) { nutrient in
                legend(
                    LocalizedStringKey(nutrient.localizedName),
                    value: "\(Format.grams(sum[nutrient] / count)) g",
                    color: nutrient.tint
                )
                if nutrient != .fat { Spacer() }
            }
        }
        .font(.caption)
    }

    private func legend(_ title: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(.secondary)
                Text(value).monospacedDigit().fontWeight(.medium)
            }
        }
    }
}

/// Daily calories as bars with the target and expenditure as rules.
struct CaloriesChart: View {
    var history: [(day: Date, totals: NutrientProfile)]
    var target: Double
    var expenditure: Double

    var body: some View {
        Chart {
            ForEach(history, id: \.day) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Calories", item.totals.calories)
                )
                .foregroundStyle(item.totals.calories > target ? Color.red.opacity(0.8) : Nutrient.calories.tint)
            }
            RuleMark(y: .value("Target", target))
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            RuleMark(y: .value("Expenditure", expenditure))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }
}

/// Stacked bars of protein, carbohydrate and fat calories per day.
struct MacrosChart: View {
    var history: [(day: Date, totals: NutrientProfile)]

    private struct Slice: Identifiable {
        var day: Date
        var nutrient: Nutrient
        var calories: Double
        var id: String { "\(day.timeIntervalSince1970)-\(nutrient.rawValue)" }
    }

    private var slices: [Slice] {
        history.flatMap { item in
            [Nutrient.protein, .carbs, .fat].map { nutrient in
                Slice(day: item.day, nutrient: nutrient, calories: item.totals[nutrient] * (nutrient.kilocaloriesPerGram ?? 0))
            }
        }
    }

    var body: some View {
        Chart(slices) { slice in
            BarMark(
                x: .value("Day", slice.day, unit: .day),
                y: .value("Calories", slice.calories)
            )
            .foregroundStyle(by: .value("Macro", slice.nutrient.shortName))
        }
        .chartForegroundStyleScale([
            Nutrient.protein.shortName: Nutrient.protein.tint,
            Nutrient.carbs.shortName: Nutrient.carbs.tint,
            Nutrient.fat.shortName: Nutrient.fat.tint,
        ])
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }
}

/// Average daily intake of each tracked micronutrient as a share of the
/// reference intake, over the logged days in range.
struct MicronutrientCoverage: View {
    var history: [(day: Date, totals: NutrientProfile)]

    private var averages: NutrientProfile {
        let logged = history.filter { $0.totals.calories > 0 }
        guard !logged.isEmpty else { return .empty }
        return NutrientProfile.sum(logged.map(\.totals)).scaled(by: 1 / Double(logged.count))
    }

    var body: some View {
        let profile = averages
        let nutrients = Nutrient.micros.filter { $0.referenceDailyIntake != nil }
        if profile == .empty {
            Text("Log some days to see micronutrient coverage.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(nutrients) { nutrient in
                    NutrientProgressRow(nutrient: nutrient, amount: profile[nutrient], target: nutrient.referenceDailyIntake)
                        .font(.subheadline)
                }
            }
        }
    }
}
