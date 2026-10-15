import SwiftUI

/// Read-only view of a food with all nutrients, per 100 g or per serving.
struct FoodDetailView: View {
    @Environment(AppStore.self) private var store
    let food: FoodItem
    @State private var perServing = true
    @State private var editing = false
    @State private var logging = false

    private var nutrients: NutrientProfile {
        perServing ? food.nutrientsPerServing : food.nutrientsPer100g
    }

    var body: some View {
        List {
            Section {
                Picker("Amount", selection: $perServing) {
                    Text("1 serving (\(Format.grams(food.servingGrams)) g)").tag(true)
                    Text("100 g").tag(false)
                }
                .pickerStyle(.segmented)
                NutrientSummaryGrid(nutrients: nutrients)
                if let brand = food.brand, !brand.isEmpty {
                    LabeledContent("Brand", value: brand)
                }
                if let label = food.displayServingLabel, !label.isEmpty {
                    LabeledContent("Serving", value: label)
                }
                LabeledContent("Source", value: sourceName)
            }
            if food.isDish {
                Section("Ingredients") {
                    ForEach(food.ingredients) { ingredient in
                        HStack {
                            Text(ingredient.name)
                            Spacer()
                            Text("\(Format.grams(ingredient.grams)) g")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            ForEach(NutrientCategory.allCases) { category in
                let items = Nutrient.allCases.filter { $0.category == category && nutrients.has($0) }
                if !items.isEmpty {
                    Section(category.localizedName) {
                        ForEach(items) { nutrient in
                            LabeledContent(nutrient.localizedName, value: Format.amount(nutrients[nutrient], of: nutrient))
                        }
                    }
                }
            }
        }
        .navigationTitle(food.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.toggleFavorite(food)
                } label: {
                    Image(systemName: food.isFavorite ? "star.fill" : "star")
                }
                Button("Edit") { editing = true }
                Button {
                    logging = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Log this food")
            }
        }
        .sheet(isPresented: $editing) {
            FoodEditorView(food: food)
        }
        .sheet(isPresented: $logging) {
            FoodPortionSheet(food: food) { grams in
                store.log(food, grams: grams, at: Date())
            }
        }
    }

    private var sourceName: String {
        switch food.source {
        case .seed: return String(localized: "source.seed")
        case .user: return String(localized: "source.user")
        case .ai: return String(localized: "source.ai")
        }
    }
}
