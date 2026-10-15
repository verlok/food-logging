import Foundation
#if !SWIFTDATA_SHIM
import SwiftData
#endif
import Observation

/// A body-weight measurement. One entry per day; logging again on the same
/// day replaces the earlier value.
#if SWIFTDATA_SHIM
@Observable
#else
@Model
#endif
final class WeightEntry {
    var id: UUID
    /// Start of the day of the measurement, in the local calendar.
    var day: Date
    var weightKg: Double
    var createdAt: Date

    init(id: UUID = UUID(), day: Date, weightKg: Double) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: day)
        self.weightKg = weightKg
        self.createdAt = .now
    }
}
