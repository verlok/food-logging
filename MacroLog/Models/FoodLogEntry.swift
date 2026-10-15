import Foundation
#if !SWIFTDATA_SHIM
import SwiftData
#endif
import Observation

/// A portion of food logged at a point in time. There are no fixed meal
/// slots: entries are free-form and ordered by the time they were eaten.
/// The entry stores a snapshot of the food's nutrients so history never
/// changes when the food database is edited.
#if SWIFTDATA_SHIM
@Observable
#else
@Model
#endif
final class FoodLogEntry {
    var id: UUID
    /// Start of the day the entry belongs to, in the local calendar. Kept
    /// alongside `time` so day queries stay simple and fast.
    var day: Date
    /// When the food was eaten.
    var time: Date
    var foodID: UUID?
    var foodName: String
    var grams: Double
    /// Grams in one serving of the food at the time of logging.
    var servingGrams: Double
    /// Nutrients per 100 g at the time of logging, JSON encoded.
    var nutrientData: Data
    var createdAt: Date

    init(
        id: UUID = UUID(),
        time: Date,
        food: FoodItem,
        grams: Double
    ) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: time)
        self.time = time
        self.foodID = food.id
        self.foodName = food.displayName
        self.grams = grams
        self.servingGrams = food.servingGrams
        self.nutrientData = food.nutrientData
        self.createdAt = .now
    }

    /// Creates a free-form entry (e.g. a "quick add" of calories and macros)
    /// that is not backed by a food item.
    init(
        id: UUID = UUID(),
        time: Date,
        name: String,
        nutrients: NutrientProfile
    ) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: time)
        self.time = time
        self.foodID = nil
        self.foodName = name
        self.grams = 100
        self.servingGrams = 100
        self.nutrientData = nutrients.encoded()
        self.createdAt = .now
    }

    /// Moves the entry to another moment, keeping `day` consistent.
    func setTime(_ newTime: Date) {
        time = newTime
        day = Calendar.current.startOfDay(for: newTime)
    }

    /// A new, unsaved entry with the same content at another moment.
    func copy(to newTime: Date) -> FoodLogEntry {
        let clone = FoodLogEntry(time: newTime, name: foodName, nutrients: nutrientsPer100g)
        clone.foodID = foodID
        clone.grams = grams
        clone.servingGrams = servingGrams
        return clone
    }

    var nutrientsPer100g: NutrientProfile {
        get { NutrientProfile.decode(nutrientData) }
        set { nutrientData = newValue.encoded() }
    }

    /// Nutrients actually eaten in this entry.
    var nutrients: NutrientProfile {
        nutrientsPer100g.scaled(by: grams / 100)
    }

    var servings: Double {
        servingGrams > 0 ? grams / servingGrams : 0
    }
}

extension Date {
    /// Combines the calendar day of `day` with the clock time of `time`.
    static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let clock = calendar.dateComponents([.hour, .minute, .second], from: time)
        return calendar.date(
            bySettingHour: clock.hour ?? 0,
            minute: clock.minute ?? 0,
            second: clock.second ?? 0,
            of: calendar.startOfDay(for: day)
        ) ?? day
    }

    /// The moment to pre-select when logging on `day`: now when the day is
    /// today, otherwise the current clock time on that day.
    static func suggestedLogTime(on day: Date, now: Date = .now) -> Date {
        Calendar.current.isDate(day, inSameDayAs: now) ? now : combine(day: day, time: now)
    }
}
