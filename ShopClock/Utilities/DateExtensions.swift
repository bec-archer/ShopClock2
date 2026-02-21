import Foundation

extension Date {
    /// Returns the start of the week (Monday) containing this date
    var startOfWeek: Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        components.weekday = 2 // Monday
        return calendar.date(from: components) ?? self
    }

    /// Formatted as "8:32 AM"
    var shortTime: String {
        self.formatted(date: .omitted, time: .shortened)
    }

    /// Formatted as "Mon, Feb 10"
    var shortDate: String {
        self.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Formatted as "2/10"
    var compactDate: String {
        self.formatted(.dateTime.month(.defaultDigits).day())
    }

    /// Is this date today?
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Returns all 7 dates for the week starting on this date (assumed Monday)
    func weekDates() -> [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: self) }
    }
}

extension Double {
    /// Format hours nicely: "8.5 hrs" or "0.0 hrs"
    var hoursFormatted: String {
        String(format: "%.1f hrs", self)
    }
}
