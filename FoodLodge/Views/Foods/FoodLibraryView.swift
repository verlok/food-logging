import SwiftUI

/// Browse and manage the food database.
struct FoodLibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var editingFood: FoodItem?
    @State private var creating = false
    @State private var showingAI = false

    enum Filter: String, CaseIterable, Identifiable {
        case all, favorites, custom, dishes
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .all: return "All"
            case .favorites: return "Favorites"
            case .custom: return "Mine"
            case .dishes: return "Dishes"
            }
        }
    }

    private var foods: [FoodItem] {
        let base: [FoodItem]
        switch filter {
        case .all: base = store.foods
        case .favorites: base = store.favoriteFoods
        case .custom: base = store.customFoods
        case .dishes: base = store.foods.filter(\.isDish)
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return base.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } }
        let matches = Set(store.search(trimmed).map(\.id))
        return base.filter { matches.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(foods, id: \.id) { food in
                        NavigationLink(value: food.id) {
                            FoodLibraryRow(food: food)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.toggleFavorite(food)
                            } label: {
                                Label("Favorite", systemImage: food.isFavorite ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing) {
                            if food.source != .seed {
                                Button(role: .destructive) {
                                    store.delete(food)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            Button {
                                editingFood = food
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                    }
                } footer: {
                    Text("foods.count \(foods.count)")
                }
            }
            .searchable(text: $query, prompt: "Search foods")
            .navigationTitle("Foods")
            .navigationDestination(for: UUID.self) { id in
                if let food = store.food(withID: id) {
                    FoodDetailView(food: food)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            creating = true
                        } label: {
                            Label("Create a food", systemImage: "plus.square.on.square")
                        }
                        Button {
                            showingAI = true
                        } label: {
                            Label("Describe or photograph a dish", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingFood) { food in
                FoodEditorView(food: food)
            }
            .sheet(isPresented: $creating) {
                FoodEditorView(food: nil)
            }
            .sheet(isPresented: $showingAI) {
                AIDishView { _ in }
            }
        }
    }
}

struct FoodLibraryRow: View {
    let food: FoodItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(food.displayName).lineLimit(1)
                    if food.isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 6) {
                    if let brand = food.brand, !brand.isEmpty { Text(brand) }
                    MacroSummaryText(nutrients: food.nutrientsPer100g)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Format.kcal(food.nutrientsPer100g.calories)) kcal")
                    .monospacedDigit()
                Text("per 100 g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
