import SwiftUI

/// Sheet used to add food at a moment of the day. Designed around the fewest taps:
/// recents appear immediately, and the "+" on a row logs one serving at
/// once without opening the portion screen.
struct FoodSearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// When the food is eaten; defaults to now (or the current clock time
    /// on the selected day) and can be adjusted from the toolbar.
    @State var time: Date
    @State private var query = ""
    @State private var scope: Scope = .recent
    @State private var portionFood: FoodItem?
    @State private var showingEditor = false
    @State private var showingAI = false
    @State private var justAdded: String?

    enum Scope: String, CaseIterable, Identifiable {
        case recent, all, favorites, custom
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .recent: return "Recent"
            case .all: return "All"
            case .favorites: return "Favorites"
            case .custom: return "Mine"
            }
        }
    }

    private var results: [FoodItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return store.search(trimmed) }
        switch scope {
        case .recent:
            let recents = store.recentFoods
            return recents.isEmpty ? store.foods : recents
        case .all: return store.foods
        case .favorites: return store.favoriteFoods
        case .custom: return store.customFoods
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        Picker("Scope", selection: $scope) {
                            ForEach(Scope.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
                Section {
                    Button {
                        showingAI = true
                    } label: {
                        Label("Describe or photograph a dish", systemImage: "sparkles")
                    }
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Create a food", systemImage: "plus.square.on.square")
                    }
                }
                Section {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(results, id: \.id) { food in
                        FoodSearchRow(food: food) {
                            logServing(of: food)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { portionFood = food }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search foods")
            .navigationTitle("Add food")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel("Time")
                }
            }
            .overlay(alignment: .bottom) {
                if let justAdded {
                    Label(justAdded, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(item: $portionFood) { food in
                FoodPortionSheet(food: food) { grams in
                    store.log(food, grams: grams, at: time)
                    flash(food.displayName)
                }
            }
            .sheet(isPresented: $showingEditor) {
                FoodEditorView(food: nil) { food in
                    portionFood = food
                }
            }
            .sheet(isPresented: $showingAI) {
                AIDishView { food in
                    portionFood = food
                }
            }
        }
    }

    private func logServing(of food: FoodItem) {
        store.log(food, grams: food.servingGrams, at: time)
        flash(food.displayName)
    }

    private func flash(_ name: String) {
        withAnimation { justAdded = String(localized: "added.toast \(name)") }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { if justAdded != nil { justAdded = nil } }
        }
    }
}

struct FoodSearchRow: View {
    let food: FoodItem
    var onQuickAdd: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(food.displayName).lineLimit(1)
                    if food.isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                    if food.isDish {
                        Image(systemName: "frying.pan").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(servingDescription)
                    MacroSummaryText(nutrients: food.nutrientsPerServing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Format.kcal(food.nutrientsPerServing.calories))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(action: onQuickAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Add one serving of \(food.displayName)"))
        }
    }

    private var servingDescription: String {
        let grams = "\(Format.grams(food.servingGrams)) g"
        if let label = food.displayServingLabel, !label.isEmpty { return "\(label) (\(grams))" }
        return grams
    }
}
