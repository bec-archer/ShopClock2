import Foundation
import SwiftData

@Model
final class ClockEvent {
    var id: UUID
    var clockIn: Date
    var clockOut: Date?

    /// Gaps recorded during this clock event (mid-day exits/returns)
    @Relationship(deleteRule: .cascade)
    var gaps: [GapEntry]

    var isActive: Bool {
        clockOut == nil
    }

    /// Total worked duration accounting for gaps (deleted gaps count as worked time)
    var workedDuration: TimeInterval {
        let end = clockOut ?? Date()
        let totalElapsed = end.timeIntervalSince(clockIn)
        let activeGapTime = gaps
            .filter { !$0.isDeleted }
            .reduce(0.0) { $0 + $1.duration }
        return max(totalElapsed - activeGapTime, 0)
    }

    var workedHours: Double {
        workedDuration / 3600.0
    }

    /// Worked hours that fall within a specific calendar day.
    /// Handles events that span across midnight (e.g., forgot to clock out yesterday).
    func workedHours(on date: Date) -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let effectiveStart = max(clockIn, startOfDay)
        let effectiveEnd = min(clockOut ?? Date(), endOfDay)

        guard effectiveEnd > effectiveStart else { return 0 }

        let totalSeconds = effectiveEnd.timeIntervalSince(effectiveStart)

        // Subtract only the portion of each gap that falls within this day
        let gapSeconds = gaps
            .filter { !$0.isDeleted }
            .reduce(0.0) { total, gap in
                let gapStart = max(gap.exitTime, startOfDay)
                let gapEnd = min(gap.returnTime ?? Date(), endOfDay)
                guard gapEnd > gapStart else { return total }
                return total + gapEnd.timeIntervalSince(gapStart)
            }

        return max(totalSeconds - gapSeconds, 0) / 3600.0
    }

    init(clockIn: Date = Date(), clockOut: Date? = nil) {
        self.id = UUID()
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.gaps = []
    }
}
