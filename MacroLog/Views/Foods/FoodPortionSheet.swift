import SwiftUI

/// Chooses how much of a food to log, with live nutrition.
struct FoodPortionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let food: FoodItem
    var onConfirm: (Double) -> Void

    @State private var grams: Double
    @State private var showingDetail = false

    init(food: FoodItem, onConfirm: @escaping (Double) -> Void) {
        self.food = food
        self.onConfirm = onConfirm
        _grams = State(initialValue: food.servingGrams)
    }

    private var nutrients: NutrientProfile { food.nutrients(forGrams: grams) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PortionPicker(grams: $grams, servingGrams: food.servingGrams, servingLabel: food.displayServingLabel)
                }
                Section("Nutrition") {
                    NutrientSummaryGrid(nutrients: nutrients)
                    Button {
                        showingDetail = true
                    } label: {
                        Label("All nutrients", systemImage: "list.bullet.rectangle")
                    }
                }
                if food.isDish {
                    Section("Ingredients") {
                        ForEach(food.ingredients) { ingredient in
                            HStack {
                                Text(ingredient.name)
                                Spacer()
                                Text("\(Format.grams(ingredient.grams * grams / max(food.servingGrams, 1))) g")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    Button {
                        store.toggleFavorite(food)
                    } label: {
                        Label(
                            food.isFavorite ? "Remove from favorites" : "Add to favorites",
                            systemImage: food.isFavorite ? "star.slash" : "star"
                        )
                    }
                }
            }
            .navigationTitle(food.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onConfirm(grams)
                        dismiss()
                    } label: {
                        Text("Add")
                    }
                    .disabled(grams <= 0)
                }
            }
            .sheet(isPresented: $showingDetail) {
                NavigationStack {
                    MicronutrientsView(totals: nutrients, title: "\(Format.grams(grams)) g")
                }
            }
        }
    }
}
