import SwiftUI
import SwiftData
import UserNotifications

@main
struct ShopClockApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var clockManager: ClockManager

    init() {
        // Register background task for Sunday night recalculation
        NotificationManager.registerBackgroundTask()

        let schema = Schema([
            ClockEvent.self,
            GapEntry.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            self.modelContainer = container
            _clockManager = StateObject(wrappedValue: ClockManager(
                modelContext: container.mainContext,
                locationManager: .shared
            ))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(locationManager)
                .environmentObject(notificationManager)
                .environmentObject(clockManager)
        }
        .modelContainer(modelContainer)
    }
}

/// Root view that handles one-time setup (permissions, geofence, notifications)
struct AppRootView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var clockManager: ClockManager
    @Environment(\.modelContext) private var modelContext

    @State private var showWeeklySummary = false
    @State private var summaryWeekStart: Date?

    var body: some View {
        MainView()
            .sheet(isPresented: $showWeeklySummary) {
                if let weekStart = summaryWeekStart {
                    NavigationStack {
                        WeekView(weekStart: weekStart)
                            .environmentObject(clockManager)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { showWeeklySummary = false }
                                }
                            }
                    }
                }
            }
            .task {
                await initialize()
            }
    }

    private func initialize() async {
        // Request permissions
        locationManager.requestAlwaysAuthorization()
        await notificationManager.requestAuthorization()
        notificationManager.registerNotificationCategories()

        // Schedule weekly notification
        await MainActor.run {
            notificationManager.scheduleWeeklySummaryNotification(modelContext: modelContext)
        }

        // Start geofence monitoring if location is set
        let workplaceLocationSet = UserDefaults.standard.bool(forKey: "workplaceLocationSet")
        if workplaceLocationSet {
            let lat = UserDefaults.standard.double(forKey: "workplaceLatitude")
            let lon = UserDefaults.standard.double(forKey: "workplaceLongitude")
            let radius = UserDefaults.standard.double(forKey: "geofenceRadius")
            locationManager.startMonitoring(latitude: lat, longitude: lon, radius: max(radius, 50))
        }

        // Setup notification response handling
        setupNotificationHandling()
    }

    private func setupNotificationHandling() {
        let delegate = NotificationDelegate { weekStart in
            summaryWeekStart = weekStart
            showWeeklySummary = true
        }
        UNUserNotificationCenter.current().delegate = delegate
        NotificationDelegate.shared = delegate
    }
}

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static var shared: NotificationDelegate?

    let onWeeklySummaryTapped: (Date) -> Void

    init(onWeeklySummaryTapped: @escaping (Date) -> Void) {
        self.onWeeklySummaryTapped = onWeeklySummaryTapped
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let weekStartInterval = userInfo["weekStart"] as? TimeInterval {
            let weekStart = Date(timeIntervalSince1970: weekStartInterval)

            DispatchQueue.main.async {
                self.onWeeklySummaryTapped(weekStart)
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
