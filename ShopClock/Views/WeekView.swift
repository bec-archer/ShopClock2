import SwiftUI

struct WeekView: View {
    @EnvironmentObject var clockManager: ClockManager

    var weekStart: Date? = nil

    private var effectiveWeekStart: Date {
        weekStart ?? ClockManager.currentWeekStart()
    }

    private var summary: WeeklySummary {
        clockManager.weeklySummary(for: effectiveWeekStart)
    }

    var body: some View {
        List {
            // Week Total
            Section {
                VStack(spacing: 8) {
                    Text(summary.totalHours.hoursFormatted)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    Text("Week of \(effectiveWeekStart.compactDate)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Daily Breakdown
            Section("Daily Breakdown") {
                ForEach(summary.dailyBreakdown) { entry in
                    NavigationLink {
                        DayDetailView(date: entry.date)
                    } label: {
                        HStack {
                            Text(entry.dayName)
                                .font(.body.bold())
                                .frame(width: 44, alignment: .leading)

                            // Mini bar chart
                            GeometryReader { geometry in
                                let maxWidth = geometry.size.width
                                let barWidth = entry.hours > 0 ? max(4, (entry.hours / 12.0) * maxWidth) : 0
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(barColor(for: entry.hours))
                                    .frame(width: barWidth, height: 20)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }

                            Text(entry.hours > 0 ? entry.hours.hoursFormatted : "—")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(entry.hours > 0 ? .primary : .tertiary)
                                .frame(width: 70, alignment: .trailing)
                        }
                        .frame(height: 36)
                    }
                    // All days are tappable — 0-hour days open DayDetailView where you can add an entry
                }
            }

            // Text to Payroll
            Section {
                Button {
                    textToRecipient()
                } label: {
                    Label("Text to Payroll", systemImage: "message.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(summary.totalHours == 0)
            }
        }
        .navigationTitle("Week View")
    }

    private func barColor(for hours: Double) -> Color {
        if hours >= 9 { return .blue }
        if hours >= 6 { return .cyan }
        if hours > 0 { return .cyan.opacity(0.6) }
        return .clear
    }

    private func textToRecipient() {
        let recipientNumber = UserDefaults.standard.string(forKey: "recipientPhoneNumber") ?? ""
        guard !recipientNumber.isEmpty else { return }

        let message = clockManager.weeklyTextMessage(for: effectiveWeekStart)
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "sms:\(recipientNumber)?body=\(encodedMessage)"

        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
