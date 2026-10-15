import SwiftUI
import Charts

/// Body-weight log with trend and history.
struct WeightView: View {
    @Environment(AppStore.self) private var store
    @State private var showingAdd = false
    @State private var range: ChartRange = .month

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                }
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    WeightChart(series: store.weightSeries, days: range.days)
                        .frame(height: 220)
                } header: {
                    Text("Trend")
                } footer: {
                    Text("weight.trend.footer")
                }
                Section("History") {
                    if store.weights.isEmpty {
                        Text("No weight logged yet").foregroundStyle(.secondary)
                    }
                    ForEach(store.weights.reversed(), id: \.id) { entry in
                        HStack {
                            Text(entry.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                            Spacer()
                            if let trend = WeightTrend.trend(on: entry.day, in: store.weightSeries) {
                                Text(Format.weight(trend))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Text(Format.weight(entry.weightKg))
                                .monospacedDigit()
                                .frame(width: 70, alignment: .trailing)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteWeight(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Weight")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Log weight")
                }
            }
            .sheet(isPresented: $showingAdd) {
                LogWeightSheet()
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trend weight").font(.caption).foregroundStyle(.secondary)
                Text(store.currentWeightKg.map(Format.weight) ?? "–")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                if let latest = store.latestMeasurementKg {
                    Text("weight.latest \(Format.weight(latest))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                change(label: "7 days", days: 7)
                change(label: "30 days", days: 30)
            }
        }
        .padding(.vertical, 4)
    }

    private func change(label: LocalizedStringKey, days: Int) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let delta = store.trendChange(overDays: days) {
                Text(Format.signedWeight(delta))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: delta))
            } else {
                Text(verbatim: "–").foregroundStyle(.tertiary)
            }
        }
    }

    private func color(for delta: Double) -> Color {
        switch store.profile.goal {
        case .lose: return delta <= 0 ? .green : .orange
        case .gain: return delta >= 0 ? .green : .orange
        case .maintain: return abs(delta) < 0.5 ? .green : .orange
        }
    }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case week, month, quarter, year
    var id: String { rawValue }
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .week: return "1W"
        case .month: return "1M"
        case .quarter: return "3M"
        case .year: return "1Y"
        }
    }
}

/// Scatter of measurements plus the smoothed trend line.
struct WeightChart: View {
    var series: [TrendPoint]
    var days: Int

    private var visible: [TrendPoint] {
        let cutoff = Date().startOfDay.adding(days: -days)
        return series.filter { $0.day >= cutoff }
    }

    private var domain: ClosedRange<Double> {
        let values = visible.flatMap { [$0.trendKg] + ($0.weightKg.map { [$0] } ?? []) }
        guard let min = values.min(), let max = values.max() else { return 50...100 }
        let padding = Swift.max((max - min) * 0.2, 1)
        return (min - padding)...(max + padding)
    }

    var body: some View {
        if visible.isEmpty {
            ContentUnavailableView("No data in this range", systemImage: "scalemass")
        } else {
            Chart {
                ForEach(visible) { point in
                    if let weight = point.weightKg {
                        PointMark(
                            x: .value("Day", point.day),
                            y: .value("Weight", weight)
                        )
                        .foregroundStyle(.secondary.opacity(0.6))
                        .symbolSize(20)
                    }
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Trend", point.trendKg)
                    )
                    .foregroundStyle(.tint)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
            }
            .chartYScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
    }
}

/// Minimal sheet to log today's weight with as few taps as possible.
struct LogWeightSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double?
    @State private var date = Date()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(
                            store.latestMeasurementKg.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "70.0",
                            value: $weight,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        Text(verbatim: "kg").font(.title2).foregroundStyle(.secondary)
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }
            }
            .navigationTitle("Log weight")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let weight { store.logWeight(weight, on: date) }
                        dismiss()
                    }
                    .disabled(weight == nil || (weight ?? 0) <= 0)
                }
            }
            .onAppear { focused = true }
        }
    }
}
