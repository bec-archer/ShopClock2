import Foundation
import UserNotifications
import SwiftData
import BackgroundTasks

/// Handles scheduling the Monday 8 AM weekly summary notification.
/// The notification is non-repeating so we can update its content each time.
/// It gets rescheduled on every app launch, every clock-out, and via
/// a BGAppRefreshTask that iOS runs Sunday night.
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private static let weeklyNotificationID = "com.shopclock.weekly-summary"
    static let backgroundTaskID = "com.shopclock.refresh-weekly-summary"

    @Published var isAuthorized: Bool = false

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.isAuthorized = granted
            }
        } catch {
            print("Notification authorization failed: \(error)")
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        await MainActor.run {
            self.isAuthorized = settings.authorizationStatus == .authorized
        }
    }

    /// Schedule (or reschedule) the Monday 8 AM notification with the latest weekly hours.
    /// Non-repeating so content stays fresh — we reschedule it frequently.
    @MainActor
    func scheduleWeeklySummaryNotification(modelContext: ModelContext) {
        // Remove existing
        center.removePendingNotificationRequests(withIdentifiers: [Self.weeklyNotificationID])

        // Figure out which week to report
        let calendar = Calendar.current
        let now = Date()
        let currentWeekStart = ClockManager.currentWeekStart()
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!

        // If it's Monday before 8 AM, report last week (notification fires in minutes).
        // Otherwise, report the current week (notification fires next Monday).
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let weekToReport = (weekday == 2 && hour < 8) ? lastWeekStart : currentWeekStart

        let totalHours = calculateWeeklyHours(weekStart: weekToReport, modelContext: modelContext)
        let dateStr = weekToReport.formatted(.dateTime.month(.defaultDigits).day(.twoDigits).year())

        let content = UNMutableNotificationContent()
        content.title = "ShopClock Weekly Summary"
        content.body = "Hours for week of \(dateStr): \(String(format: "%.1f", totalHours)) hrs. Tap to text to payroll."
        content.sound = .default
        content.categoryIdentifier = "WEEKLY_SUMMARY"
        content.userInfo = ["weekStart": weekToReport.timeIntervalSince1970]

        // Fire next Monday at 8:00 AM (non-repeating)
        var dateComponents = DateComponents()
        dateComponents.weekday = 2  // Monday
        dateComponents.hour = 8
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.weeklyNotificationID,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("Failed to schedule weekly notification: \(error)")
            }
        }

        // Schedule background refresh for Sunday night to get final numbers
        scheduleSundayNightRefresh()
    }

    /// Register notification actions (Text Payroll / Dismiss)
    func registerNotificationCategories() {
        let textAction = UNNotificationAction(
            identifier: "TEXT_RECIPIENT",
            title: "Text to Payroll",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: "WEEKLY_SUMMARY",
            actions: [textAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
    }

    // MARK: - Background App Refresh

    /// Register the background task. Call once in App.init().
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskID,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleBackgroundRefresh(task: refreshTask)
        }
    }

    /// Schedule a background refresh for Sunday at 11:59 PM
    private func scheduleSundayNightRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)

        // Find next Sunday at 11:59 PM
        if let nextSunday = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 23, minute: 59, weekday: 1),
            matchingPolicy: .nextTime
        ) {
            request.earliestBeginDate = nextSunday
        }

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule Sunday night refresh: \(error)")
        }
    }

    /// Background refresh handler — recalculate hours and reschedule the Monday notification
    private static func handleBackgroundRefresh(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        let schema = Schema([ClockEvent.self, GapEntry.self])
        guard let container = try? ModelContainer(for: schema) else {
            task.setTaskCompleted(success: false)
            return
        }

        Task { @MainActor in
            let context = container.mainContext
            NotificationManager.shared.scheduleWeeklySummaryNotification(modelContext: context)
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Helpers

    @MainActor
    private func calculateWeeklyHours(weekStart: Date, modelContext: ModelContext) -> Double {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        let descriptor = FetchDescriptor<ClockEvent>(
            predicate: #Predicate<ClockEvent> {
                $0.clockIn >= weekStart && $0.clockIn < weekEnd
            }
        )

        guard let events = try? modelContext.fetch(descriptor) else { return 0 }
        return events.reduce(0.0) { $0 + $1.workedHours }
    }
}
