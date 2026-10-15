import Foundation

/// Shared number and date formatting so values look the same everywhere.
enum Format {
    static func kcal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func grams(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(0...decimals)))
    }

    static func amount(_ value: Double, of nutrient: Nutrient) -> String {
        let decimals: Int
        switch nutrient.unit {
        case .kilocalories: decimals = 0
        case .grams: decimals = value < 10 ? 1 : 0
        case .milligrams: decimals = value < 10 ? 1 : 0
        case .micrograms: decimals = value < 10 ? 1 : 0
        }
        let number = value.formatted(.number.precision(.fractionLength(0...decimals)))
        return "\(number) \(nutrient.unit.symbol)"
    }

    static func weight(_ kg: Double) -> String {
        kg.formatted(.number.precision(.fractionLength(1))) + " kg"
    }

    static func signedWeight(_ kg: Double) -> String {
        let sign = kg > 0 ? "+" : ""
        return sign + kg.formatted(.number.precision(.fractionLength(1))) + " kg"
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func day(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if Calendar.current.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}
