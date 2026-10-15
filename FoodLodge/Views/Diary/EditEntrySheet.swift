import SwiftUI

/// Changes the portion, the day or the time of an existing diary entry.
struct EditEntrySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: FoodLogEntry

    @State private var grams: Double
    @State private var time: Date

    init(entry: FoodLogEntry) {
        self.entry = entry
        _grams = State(initialValue: entry.grams)
        _time = State(initialValue: entry.time)
    }

    private var nutrients: NutrientProfile { entry.nutrientsPer100g.scaled(by: grams / 100) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PortionPicker(grams: $grams, servingGrams: entry.servingGrams, servingLabel: nil)
                }
                Section("When") {
                    DatePicker("Day", selection: $time, displayedComponents: .date)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
                Section("Nutrition") {
                    NutrientSummaryGrid(nutrients: nutrients)
                }
                Section {
                    Button(role: .destructive) {
                        store.delete(entry)
                        dismiss()
                    } label: {
                        Label("Delete entry", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(entry.foodName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.update(entry, grams: grams, time: time)
                        dismiss()
                    }
                    .disabled(grams <= 0)
                }
            }
        }
    }
}

/// Copies or moves one entry to another day and time.
struct CopyMoveSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: FoodLogEntry
    let mode: EntryTransfer.Mode
    var onDone: (String) -> Void

    @State private var target: Date

    init(entry: FoodLogEntry, mode: EntryTransfer.Mode, onDone: @escaping (String) -> Void) {
        self.entry = entry
        self.mode = mode
        self.onDone = onDone
        _target = State(initialValue: entry.time)
    }

    private var title: LocalizedStringKey { mode == .copy ? "Copy to…" : "Move to…" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Food", value: entry.foodName)
                    LabeledContent("Portion", value: "\(Format.grams(entry.grams)) g")
                    LabeledContent("Currently", value: entry.time.formatted(date: .abbreviated, time: .shortened))
                }
                Section("Destination") {
                    DatePicker("Day", selection: $target, displayedComponents: .date)
                    DatePicker("Time", selection: $target, displayedComponents: .hourAndMinute)
                    HStack {
                        quickButton("Today", day: Date())
                        quickButton("Yesterday", day: Date().adding(days: -1))
                        quickButton("Tomorrow", day: Date().adding(days: 1))
                    }
                    Button {
                        target = Date()
                    } label: {
                        Label("Now", systemImage: "clock")
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .copy ? "Copy" : "Move") {
                        let when = target.formatted(date: .abbreviated, time: .shortened)
                        if mode == .copy {
                            store.copy(entry, to: target)
                            onDone(String(localized: "copied.toast \(entry.foodName) \(when)"))
                        } else {
                            store.move(entry, to: target)
                            onDone(String(localized: "moved.toast \(entry.foodName) \(when)"))
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private func quickButton(_ title: LocalizedStringKey, day: Date) -> some View {
        Button {
            target = Date.combine(day: day, time: target)
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

/// Copies every entry of a chosen day into the selected day.
struct CopyDaySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let targetDay: Date
    var onDone: (Int) -> Void

    @State private var sourceDay: Date

    init(targetDay: Date, onDone: @escaping (Int) -> Void) {
        self.targetDay = targetDay
        self.onDone = onDone
        _sourceDay = State(initialValue: targetDay.adding(days: -1))
    }

    private var sourceEntries: [FoodLogEntry] {
        Repository.entries(on: sourceDay, in: store.context).sorted { $0.time < $1.time }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Copy from", selection: $sourceDay, in: ...Date().adding(days: 365), displayedComponents: .date)
                    LabeledContent("Into", value: Format.day(targetDay))
                }
                Section("Entries to copy") {
                    let entries = sourceEntries
                    if entries.isEmpty {
                        Text("Nothing logged on that day").foregroundStyle(.secondary)
                    }
                    ForEach(entries, id: \.id) { entry in
                        EntryRow(entry: entry)
                    }
                }
            }
            .navigationTitle("Copy from another day")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        let count = store.copyEntries(from: sourceDay, to: targetDay)
                        onDone(count)
                        dismiss()
                    }
                    .disabled(sourceEntries.isEmpty || Calendar.current.isDate(sourceDay, inSameDayAs: targetDay))
                }
            }
        }
    }
}

/// Grams field with quick serving multipliers. Shared by every place that
/// asks for a portion.
struct PortionPicker: View {
    @Binding var grams: Double
    var servingGrams: Double
    var servingLabel: String?

    private var servings: Double { servingGrams > 0 ? grams / servingGrams : 0 }

    var body: some View {
        HStack {
            Text("Grams")
            Spacer()
            TextField("Grams", value: $grams, format: .number.precision(.fractionLength(0...1)))
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(verbatim: "g").foregroundStyle(.secondary)
        }
        if servingGrams > 0 {
            HStack {
                if let servingLabel, !servingLabel.isEmpty {
                    Text("servings.labelled \(servingLabel)")
                } else {
                    Text("Servings")
                }
                Spacer()
                Stepper(
                    value: Binding(
                        get: { servings },
                        set: { grams = ($0 * servingGrams * 10).rounded() / 10 }
                    ),
                    in: 0...50,
                    step: 0.5
                ) {
                    Text(servings.formatted(.number.precision(.fractionLength(0...1))))
                        .monospacedDigit()
                }
            }
            HStack {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { multiplier in
                    Button {
                        grams = (multiplier * servingGrams * 10).rounded() / 10
                    } label: {
                        Text(verbatim: "×\(multiplier.formatted(.number.precision(.fractionLength(0...1))))")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

/// Four-up grid with calories and macros.
struct NutrientSummaryGrid: View {
    var nutrients: NutrientProfile

    var body: some View {
        HStack {
            ForEach(Nutrient.macros) { nutrient in
                VStack(spacing: 2) {
                    Text(Format.amount(nutrients[nutrient], of: nutrient))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(nutrient.shortName)
                        .font(.caption)
                        .foregroundStyle(nutrient.tint)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
