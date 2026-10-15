import SwiftUI

/// Logs calories and macros without a food, for restaurant meals or labels
/// the user does not want to save.
struct QuickAddSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var time: Date
    @State private var name = ""
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    /// Calories implied by the macros when the user leaves calories empty.
    private var impliedCalories: Double {
        (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name)
                    DatePicker("Time", selection: $time, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Nutrition") {
                    numberField("Calories", value: $calories, unit: "kcal", prompt: Format.kcal(impliedCalories))
                    numberField("Protein", value: $protein, unit: "g")
                    numberField("Carbohydrates", value: $carbs, unit: "g")
                    numberField("Fat", value: $fat, unit: "g")
                }
            }
            .navigationTitle("Quick add")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let nutrients = NutrientProfile(
                            calories: calories ?? impliedCalories,
                            protein: protein ?? 0,
                            carbs: carbs ?? 0,
                            fat: fat ?? 0
                        )
                        let label = name.isEmpty ? String(localized: "Quick add") : name
                        store.quickAdd(name: label, nutrients: nutrients, at: time)
                        dismiss()
                    }
                    .disabled((calories ?? impliedCalories) <= 0)
                }
            }
        }
    }

    private func numberField(_ title: LocalizedStringKey, value: Binding<Double?>, unit: String, prompt: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(prompt ?? "0", value: value, format: .number.precision(.fractionLength(0...1)))
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(verbatim: unit).foregroundStyle(.secondary)
        }
    }
}
