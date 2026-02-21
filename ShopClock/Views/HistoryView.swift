import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var clockManager: ClockManager

    private var weekStarts: [Date] {
        clockManager.allWeekStarts()
    }

    var body: some View {
        List {
            if weekStarts.isEmpty {
                ContentUnavailableView {
                    Label("No History", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Clock in at the workplace to start tracking hours.")
                }
            } else {
                ForEach(weekStarts, id: \.self) { weekStart in
                    NavigationLink {
                        WeekView(weekStart: weekStart)
                    } label: {
                        weekRow(weekStart: weekStart)
                    }
                }
            }
        }
        .navigationTitle("History")
    }

    private func weekRow(weekStart: Date) -> some View {
        let summary = clockManager.weeklySummary(for: weekStart)
        let endDate = Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Week of \(weekStart.compactDate)")
                    .font(.body.bold())

                Text("\(weekStart.shortDate) – \(endDate.shortDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(summary.totalHours.hoursFormatted)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}
