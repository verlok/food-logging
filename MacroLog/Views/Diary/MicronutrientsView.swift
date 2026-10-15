import SwiftUI

/// Full nutrient breakdown of a day (or any nutrient profile) against the
/// reference daily intakes.
struct MicronutrientsView: View {
    @Environment(\.dismiss) private var dismiss
    var totals: NutrientProfile
    var title: String
    var targets: DailyTargets?

    var body: some View {
        List {
            ForEach(NutrientCategory.allCases) { category in
                let nutrients = Nutrient.allCases.filter { $0.category == category }
                Section(category.localizedName) {
                    ForEach(nutrients) { nutrient in
                        NutrientProgressRow(
                            nutrient: nutrient,
                            amount: totals[nutrient],
                            target: targets?.target(for: nutrient) ?? nutrient.referenceDailyIntake
                        )
                    }
                }
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
