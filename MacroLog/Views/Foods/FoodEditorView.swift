import SwiftUI

/// Creates or edits a food. Values are entered per reference amount (100 g
/// by default, or per serving) and normalised to 100 g on save.
struct FoodEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let food: FoodItem?
    var onSave: ((FoodItem) -> Void)?

    @State private var name: String
    @State private var brand: String
    @State private var servingGrams: Double
    @State private var servingLabel: String
    @State private var perServing = false
    @State private var values: [Nutrient: Double?]
    @State private var showingMicros = false

    init(food: FoodItem?, onSave: ((FoodItem) -> Void)? = nil) {
        self.food = food
        self.onSave = onSave
        _name = State(initialValue: food?.name ?? "")
        _brand = State(initialValue: food?.brand ?? "")
        _servingGrams = State(initialValue: food?.servingGrams ?? 100)
        _servingLabel = State(initialValue: food?.servingLabel ?? "")
        var initial: [Nutrient: Double?] = [:]
        if let food {
            let profile = food.nutrientsPer100g
            for nutrient in Nutrient.allCases where profile.has(nutrient) {
                initial[nutrient] = profile[nutrient]
            }
        }
        _values = State(initialValue: initial)
    }

    /// Multiplier that converts entered values to per-100 g.
    private var normalisation: Double {
        perServing && servingGrams > 0 ? 100 / servingGrams : 1
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (values[.calories] ?? nil) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }
                Section("Serving") {
                    HStack {
                        Text("Serving size")
                        Spacer()
                        TextField("100", value: $servingGrams, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(verbatim: "g").foregroundStyle(.secondary)
                    }
                    TextField("Serving name, e.g. 1 slice", text: $servingLabel)
                }
                Section {
                    Picker("Values are per", selection: $perServing) {
                        Text("100 g").tag(false)
                        Text("1 serving").tag(true)
                    }
                    .pickerStyle(.segmented)
                    ForEach(Nutrient.macros) { nutrient in
                        nutrientField(nutrient)
                    }
                    ForEach([Nutrient.fiber, .sugar, .saturatedFat, .sodium]) { nutrient in
                        nutrientField(nutrient)
                    }
                } header: {
                    Text("Nutrition")
                } footer: {
                    Text("Only calories are required.")
                }
                Section {
                    DisclosureGroup("More micronutrients", isExpanded: $showingMicros) {
                        ForEach(Nutrient.micros.filter { ![.fiber, .sugar, .saturatedFat, .sodium].contains($0) }) { nutrient in
                            nutrientField(nutrient)
                        }
                    }
                }
                if let food, food.source != .seed {
                    Section {
                        Button(role: .destructive) {
                            store.delete(food)
                            dismiss()
                        } label: {
                            Label("Delete food", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(food == nil ? "New food" : "Edit food")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func nutrientField(_ nutrient: Nutrient) -> some View {
        HStack {
            Text(nutrient.localizedName)
            Spacer()
            TextField(
                "–",
                value: Binding(
                    get: { values[nutrient] ?? nil },
                    set: { values[nutrient] = $0 }
                ),
                format: .number.precision(.fractionLength(0...2))
            )
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            Text(verbatim: nutrient.unit.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    private func save() {
        var profile: [Nutrient: Double] = [:]
        for (nutrient, value) in values {
            if let value { profile[nutrient] = value * normalisation }
        }
        let nutrients = NutrientProfile(profile)
        let trimmedLabel = servingLabel.trimmingCharacters(in: .whitespaces)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)

        if let food {
            food.name = name.trimmingCharacters(in: .whitespaces)
            food.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
            food.servingGrams = max(servingGrams, 1)
            food.servingLabel = trimmedLabel.isEmpty ? nil : trimmedLabel
            food.nutrientsPer100g = nutrients
            if food.source == .seed { food.translations = [:]; food.servingLabelTranslations = [:] }
            store.foodDidChange()
            onSave?(food)
        } else {
            let created = FoodItem(
                name: name.trimmingCharacters(in: .whitespaces),
                brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
                servingGrams: max(servingGrams, 1),
                servingLabel: trimmedLabel.isEmpty ? nil : trimmedLabel,
                nutrientsPer100g: nutrients,
                source: .user
            )
            store.insert(created)
            onSave?(created)
        }
        dismiss()
    }
}
