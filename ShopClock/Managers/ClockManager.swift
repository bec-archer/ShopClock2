import Foundation
import SwiftData
import Combine

/// Central business logic for clock in/out, grace periods, and gap tracking.
/// This is the brain of ShopClock.
@MainActor
final class ClockManager: ObservableObject {
    private let modelContext: ModelContext
    private let locationManager: LocationManager

    @Published var activeEvent: ClockEvent?
    @Published var isClockedIn: Bool = false
    @Published var todayHours: Double = 0.0
    @Published var pendingGap: GapEntry?
    /// Set to true when the app launches and user is already inside the geofence but not clocked in
    @Published var showAlreadyInsidePrompt: Bool = false

    private var gracePeriodTimer: Timer?
    private var hourUpdateTimer: Timer?
    private var isFirstLaunchCheck = true

    /// Grace period in seconds before a geofence exit triggers a real gap
    var gracePeriodSeconds: TimeInterval {
        Double(UserDefaults.standard.integer(forKey: "gracePeriodMinutes").clamped(to: 5...60)) * 60.0
    }

    init(modelContext: ModelContext, locationManager: LocationManager = .shared) {
        self.modelContext = modelContext
        self.locationManager = locationManager

        // Ensure UserDefaults has the correct default so gracePeriodSeconds
        // reads 15 (not 0 → clamped to 5) before the user ever opens Settings.
        UserDefaults.standard.register(defaults: ["gracePeriodMinutes": 15])

        loadActiveEvent()
        setupLocationCallbacks()
        startHourUpdateTimer()
    }

    // MARK: - Setup

    private func setupLocationCallbacks() {
        locationManager.onEnterRegion = { [weak self] in
            Task { @MainActor in
                self?.handleGeofenceEnter()
            }
        }
        locationManager.onExitRegion = { [weak self] in
            Task { @MainActor in
                self?.handleGeofenceExit()
            }
        }
    }

    private func startHourUpdateTimer() {
        hourUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTodayHours()
            }
        }
        updateTodayHours()
    }

    // MARK: - Load State

    private func loadActiveEvent() {
        let descriptor = FetchDescriptor<ClockEvent>(
            predicate: #Predicate<ClockEvent> { $0.clockOut == nil },
            sortBy: [SortDescriptor(\.clockIn, order: .reverse)]
        )
        if let events = try? modelContext.fetch(descriptor) {
            activeEvent = events.first
            isClockedIn = activeEvent != nil

            // Check for open gaps
            if let active = activeEvent {
                pendingGap = active.gaps.first(where: { $0.returnTime == nil })
            }
        }
    }

    // MARK: - Geofence Handlers

    private func handleGeofenceEnter() {
        // Cancel any pending grace period timer
        gracePeriodTimer?.invalidate()
        gracePeriodTimer = nil

        if let gap = pendingGap {
            // Returning from a gap — close it
            gap.returnTime = Date()
            pendingGap = nil
            try? modelContext.save()
            updateTodayHours()
        } else if !isClockedIn && !showAlreadyInsidePrompt {
            if isFirstLaunchCheck {
                // User was already inside the geofence when app launched — prompt instead of auto clock-in
                isFirstLaunchCheck = false
                showAlreadyInsidePrompt = true
            } else {
                // Normal geofence entry — auto clock in
                clockIn()
            }
        }
        isFirstLaunchCheck = false
    }

    private func handleGeofenceExit() {
        guard isClockedIn, activeEvent != nil else { return }

        // Start grace period timer
        let exitTime = Date()
        gracePeriodTimer?.invalidate()
        gracePeriodTimer = Timer.scheduledTimer(withTimeInterval: gracePeriodSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let active = self.activeEvent else { return }
                self.commitGap(for: active, exitTime: exitTime)
            }
        }
    }

    /// Called when the grace period expires — the exit is real
    private func commitGap(for event: ClockEvent, exitTime: Date) {
        let gap = GapEntry(exitTime: exitTime)
        gap.clockEvent = event
        event.gaps.append(gap)
        pendingGap = gap
        modelContext.insert(gap)
        try? modelContext.save()
        updateTodayHours()
    }

    // MARK: - Manual Clock In/Out

    func clockIn(at date: Date = Date()) {
        guard !isClockedIn else { return }

        let event = ClockEvent(clockIn: date)
        modelContext.insert(event)
        activeEvent = event
        isClockedIn = true
        try? modelContext.save()
        updateTodayHours()
    }

    func clockOut(at date: Date = Date()) {
        guard isClockedIn, let active = activeEvent else { return }

        // Close any open gap first
        if let gap = pendingGap {
            gap.returnTime = date
            pendingGap = nil
        }

        gracePeriodTimer?.invalidate()
        gracePeriodTimer = nil

        active.clockOut = date
        activeEvent = nil
        isClockedIn = false
        try? modelContext.save()
        updateTodayHours()

        // Update the Monday notification
        NotificationManager.shared.scheduleWeeklySummaryNotification(modelContext: modelContext)
    }

    // MARK: - Today's Hours

    func updateTodayHours() {
        todayHours = hoursForDate(Date())
    }

    func hoursForDate(_ date: Date) -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Fetch all events and filter in-memory to avoid SwiftData #Predicate
        // issues with captured local Date variables silently failing.
        let descriptor = FetchDescriptor<ClockEvent>(
            sortBy: [SortDescriptor(\.clockIn)]
        )

        guard let allEvents = try? modelContext.fetch(descriptor) else { return 0 }

        // Find events that OVERLAP with this day — not just events that started on this day.
        // This handles events that span across midnight (e.g., user forgot to clock out).
        let events = allEvents.filter { event in
            let eventEnd = event.clockOut ?? Date()
            return event.clockIn < endOfDay && eventEnd > startOfDay
        }

        // Use per-day calculation so only hours within this day are counted
        return events.reduce(0.0) { $0 + $1.workedHours(on: date) }
    }

    /// Get all clock events that overlap with a specific date
    func eventsForDate(_ date: Date) -> [ClockEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Fetch all events and filter in-memory to avoid SwiftData #Predicate
        // issues with captured local Date variables silently failing.
        let descriptor = FetchDescriptor<ClockEvent>(
            sortBy: [SortDescriptor(\.clockIn)]
        )

        let allEvents = (try? modelContext.fetch(descriptor)) ?? []

        // Find events that OVERLAP with this day
        return allEvents.filter { event in
            let eventEnd = event.clockOut ?? Date()
            return event.clockIn < endOfDay && eventEnd > startOfDay
        }
    }

    // MARK: - Weekly Summary

    func weeklySummary(for weekStart: Date) -> WeeklySummary {
        let calendar = Calendar.current
        var dailyEntries: [DayEntry] = []
        var totalHours: Double = 0

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
            let hours = hoursForDate(date)
            totalHours += hours

            let dayName = date.formatted(.dateTime.weekday(.abbreviated))
            dailyEntries.append(DayEntry(date: date, dayName: dayName, hours: hours))
        }

        return WeeklySummary(weekStarting: weekStart, totalHours: totalHours, dailyBreakdown: dailyEntries)
    }

    /// Returns the Monday of the current week
    static func currentWeekStart() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        components.weekday = 2 // Monday
        return calendar.date(from: components) ?? Date()
    }

    /// Returns all week start dates that have data, most recent first
    func allWeekStarts() -> [Date] {
        let descriptor = FetchDescriptor<ClockEvent>(
            sortBy: [SortDescriptor(\.clockIn)]
        )
        guard let events = try? modelContext.fetch(descriptor), let first = events.first else { return [] }

        let calendar = Calendar.current
        var weekStarts: [Date] = []
        var current = Self.mondayOf(first.clockIn)
        let now = Date()

        while current <= now {
            weekStarts.append(current)
            current = calendar.date(byAdding: .weekOfYear, value: 1, to: current)!
        }

        return weekStarts.reversed()
    }

    static func mondayOf(_ date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = 2
        return calendar.date(from: components) ?? date
    }

    /// Generate the text message body for a weekly summary
    func weeklyTextMessage(for weekStart: Date) -> String {
        let summary = weeklySummary(for: weekStart)
        let dateStr = weekStart.formatted(.dateTime.month(.defaultDigits).day(.twoDigits).year())
        return "My hours for week of \(dateStr): \(String(format: "%.1f", summary.totalHours))"
    }
}

// MARK: - Supporting Types

struct WeeklySummary {
    let weekStarting: Date
    let totalHours: Double
    let dailyBreakdown: [DayEntry]
}

struct DayEntry: Identifiable {
    let id = UUID()
    let date: Date
    let dayName: String
    let hours: Double
}

// MARK: - Comparable Clamping

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
