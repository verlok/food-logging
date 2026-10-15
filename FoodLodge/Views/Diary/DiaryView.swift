import SwiftUI

/// The main screen: one day of the food diary with the calorie and macro
/// budget at the top and a timeline of everything eaten below. Entries are
/// free-form and ordered by time; there are no fixed meal slots.
struct DiaryView: View {
    @Environment(AppStore.self) private var store
    @State private var showingSearch = false
    @State private var showingQuickAdd = false
    @State private var showingCopyDay = false
    @State private var editingEntry: FoodLogEntry?
    @State private var transferringEntry: EntryTransfer?
    @State private var showingMicros = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DaySummaryCard(
                        totals: store.dayTotals,
                        targets: store.targets,
                        expenditure: store.expenditure
                    )
                    .onTapGesture { showingMicros = true }

                    timeline
                }
                .padding()
                .padding(.bottom, 72)
            }
            .navigationTitle(Format.day(store.selectedDay))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    dayNavigation
                    addMenu
                }
            }
            .overlay(alignment: .bottom) {
                addButton
            }
            .overlay(alignment: .top) {
                if let toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showingSearch) {
                FoodSearchView(time: store.suggestedLogTime)
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickAddSheet(time: store.suggestedLogTime)
            }
            .sheet(isPresented: $showingCopyDay) {
                CopyDaySheet(targetDay: store.selectedDay) { count in
                    flash(String(localized: "copied.day.toast \(count)"))
                }
            }
            .sheet(item: $editingEntry) { entry in
                EditEntrySheet(entry: entry)
            }
            .sheet(item: $transferringEntry) { transfer in
                CopyMoveSheet(entry: transfer.entry, mode: transfer.mode) { message in
                    flash(message)
                }
            }
            .sheet(isPresented: $showingMicros) {
                NavigationStack {
                    MicronutrientsView(totals: store.dayTotals, title: Format.day(store.selectedDay))
                }
            }
        }
    }

    // MARK: - Toolbar

    private var dayNavigation: some View {
        HStack(spacing: 0) {
            Button {
                store.selectedDay = store.selectedDay.adding(days: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")
            Button {
                store.selectedDay = Date().startOfDay
            } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel("Today")
            .disabled(Calendar.current.isDateInToday(store.selectedDay))
            Button {
                store.selectedDay = store.selectedDay.adding(days: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next day")
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                showingSearch = true
            } label: {
                Label("Search food", systemImage: "magnifyingglass")
            }
            Button {
                showingQuickAdd = true
            } label: {
                Label("Quick add", systemImage: "bolt.fill")
            }
            Button {
                showingCopyDay = true
            } label: {
                Label("Copy from another day", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More actions")
    }

    /// Big, always-visible button: logging is the thing people do most.
    private var addButton: some View {
        Button {
            showingSearch = true
        } label: {
            Label("Add food", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .padding(.bottom, 8)
        .shadow(radius: 4, y: 2)
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Logged", systemImage: "clock")
                    .font(.headline)
                Spacer()
                if !store.dayEntries.isEmpty {
                    Text("entries.count \(store.dayEntries.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if store.dayEntries.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing logged yet")
                        .foregroundStyle(.secondary)
                    Text("diary.empty.hint")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(store.dayEntries, id: \.id) { entry in
                    EntryRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture { editingEntry = entry }
                        .contextMenu { entryMenu(entry) }
                    if entry.id != store.dayEntries.last?.id { Divider() }
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func entryMenu(_ entry: FoodLogEntry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            transferringEntry = EntryTransfer(entry: entry, mode: .copy)
        } label: {
            Label("Copy to…", systemImage: "doc.on.doc")
        }
        Button {
            transferringEntry = EntryTransfer(entry: entry, mode: .move)
        } label: {
            Label("Move to…", systemImage: "arrow.turn.down.right")
        }
        Button {
            store.copy(entry, to: Date())
            flash(String(localized: "copied.now.toast \(entry.foodName)"))
        } label: {
            Label("Copy to now", systemImage: "clock.arrow.circlepath")
        }
        Divider()
        Button(role: .destructive) {
            store.delete(entry)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func flash(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { if toast != nil { toast = nil } }
        }
    }
}

/// Identifies which entry is being copied or moved, for sheet presentation.
struct EntryTransfer: Identifiable {
    enum Mode { case copy, move }
    var entry: FoodLogEntry
    var mode: Mode
    var id: UUID { entry.id }
}

struct EntryRow: View {
    let entry: FoodLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.time.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(Format.grams(entry.grams)) g")
                    MacroSummaryText(nutrients: entry.nutrients)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.kcal(entry.nutrients.calories))
                .monospacedDigit()
                .font(.body.weight(.medium))
        }
        .padding(.vertical, 4)
    }
}

/// Calorie ring plus macro bars for the selected day.
struct DaySummaryCard: View {
    var totals: NutrientProfile
    var targets: DailyTargets
    var expenditure: ExpenditureEstimate

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                CalorieRing(eaten: totals.calories, target: targets.calories)
                    .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 10) {
                    MacroBar(nutrient: .protein, eaten: totals.protein, target: targets.protein)
                    MacroBar(nutrient: .carbs, eaten: totals.carbs, target: targets.carbs)
                    MacroBar(nutrient: .fat, eaten: totals.fat, target: targets.fat)
                }
            }
            HStack {
                statistic("Eaten", value: Format.kcal(totals.calories))
                Divider().frame(height: 28)
                statistic("Target", value: Format.kcal(targets.calories))
                Divider().frame(height: 28)
                statistic("Expenditure", value: Format.kcal(expenditure.kilocaloriesPerDay))
            }
            .font(.footnote)
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Tap for micronutrients")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .card()
    }

    private func statistic(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
