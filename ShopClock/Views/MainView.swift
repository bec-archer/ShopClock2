import SwiftUI
import SwiftData

struct MainView: View {
    @EnvironmentObject var clockManager: ClockManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var showManualClockAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status Header
                statusCard
                    .padding(.horizontal)
                    .padding(.top)

                // Today's Hours
                todayCard
                    .padding()

                // Navigation Links
                navigationSection
                    .padding(.horizontal)

                Spacer()

                // Manual Override Button
                manualOverrideButton
                    .padding()
            }
            .navigationTitle("ShopClock")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .alert("You're at the workplace", isPresented: $clockManager.showAlreadyInsidePrompt) {
                Button("Clock In") {
                    clockManager.clockIn()
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Looks like you're already at the workplace. Want to clock in?")
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 12) {
            Image(systemName: clockManager.isClockedIn ? "clock.badge.checkmark" : "clock")
                .font(.system(size: 48))
                .foregroundStyle(clockManager.isClockedIn ? .green : .secondary)
                .symbolEffect(.pulse, isActive: clockManager.isClockedIn)

            Text(clockManager.isClockedIn ? "Clocked In" : "Clocked Out")
                .font(.title2.bold())
                .foregroundStyle(clockManager.isClockedIn ? .primary : .secondary)

            if clockManager.isClockedIn, let event = clockManager.activeEvent {
                Text("Since \(event.clockIn.shortTime)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let pending = clockManager.pendingGap {
                Label("Away since \(pending.exitTime.shortTime)", systemImage: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Today Card

    private var todayCard: some View {
        VStack(spacing: 8) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(clockManager.todayHours.hoursFormatted)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Navigation

    private var navigationSection: some View {
        VStack(spacing: 12) {
            NavigationLink {
                WeekView()
            } label: {
                navRow(icon: "calendar", title: "This Week", detail: "View daily breakdown")
            }

            NavigationLink {
                HistoryView()
            } label: {
                navRow(icon: "clock.arrow.circlepath", title: "History", detail: "Past weekly summaries")
            }

            if clockManager.isClockedIn {
                NavigationLink {
                    DayDetailView(date: Date())
                } label: {
                    navRow(icon: "list.bullet", title: "Today's Gaps", detail: "View breaks & gaps")
                }
            }
        }
    }

    private func navRow(icon: String, title: String, detail: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Manual Override

    private var manualOverrideButton: some View {
        Button {
            if clockManager.isClockedIn {
                clockManager.clockOut()
            } else {
                clockManager.clockIn()
            }
        } label: {
            Label(
                clockManager.isClockedIn ? "Clock Out" : "Clock In",
                systemImage: clockManager.isClockedIn ? "stop.circle.fill" : "play.circle.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(clockManager.isClockedIn ? Color.red : Color.green, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
    }
}
