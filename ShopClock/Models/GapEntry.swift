import Foundation
import SwiftData

@Model
final class GapEntry {
    var id: UUID
    var exitTime: Date
    var returnTime: Date?
    var isDeleted: Bool

    @Relationship(inverse: \ClockEvent.gaps)
    var clockEvent: ClockEvent?

    /// Duration of the gap in seconds
    var duration: TimeInterval {
        let end = returnTime ?? Date()
        return end.timeIntervalSince(exitTime)
    }

    /// Formatted duration string (e.g., "43 min" or "1 hr 15 min")
    var formattedDuration: String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(remainingMinutes) min"
    }

    /// Whether this gap is still open (user hasn't returned yet)
    var isOpen: Bool {
        returnTime == nil
    }

    init(exitTime: Date = Date(), returnTime: Date? = nil, isDeleted: Bool = false) {
        self.id = UUID()
        self.exitTime = exitTime
        self.returnTime = returnTime
        self.isDeleted = isDeleted
    }
}
