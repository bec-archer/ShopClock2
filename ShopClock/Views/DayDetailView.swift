import SwiftUI
import SwiftData

struct DayDetailView: View {
    let date: Date

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var clockManager: ClockManager
    @State private var events: [ClockEvent] = []
    @State private var editingClockIn: ClockEvent?
    @State private var editingClockOut: ClockEvent?
    @State private var editedTime = Date()
    @State private var showAddEntry = false

    private var totalHours: Double {
        events.reduce(0.0) { $0 + $1.workedHours }
    }

    private var allGaps: [GapEntry] {
        events.flatMap { $0.gaps }.sorted { $0.exitTime < $1.exitTime }
    }

    var body: some View {
        List {
            // Hours Summary Section
            Section {
                VStack(spacing: 8) {
                    Text(totalHours.hoursFormatted)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    if let firstIn = events.first?.clockIn {
                        let lastOut = events.last?.clockOut
                        HStack {
                            // Tappable clock-in time
                            Button {
                                editedTime = firstIn
                                editingClockIn = events.first
                            } label: {
                                Label(firstIn.shortTime, systemImage: "arrow.right.circle")
                                    .underline()
                            }

                            if let out = lastOut {
                                Text("→")
                                // Tappable clock-out time
                                Button {
                                    editedTime = out
                                    editingClockOut = events.last
                                } label: {
                                    Label(out.shortTime, systemImage: "arrow.left.circle")
                                        .underline()
                                }
                            } else {
                                Text("→")
                                Text("Active")
                                    .foregroundStyle(.green)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } footer: {
                if !events.isEmpty {
                    Text("Tap a time to edit it.")
                }
            }

            // Gaps Section
            Section {
                if allGaps.isEmpty {
                    ContentUnavailableView {
                        Label("No Gaps", systemImage: "checkmark.circle")
                    } description: {
                        Text("No breaks or departures recorded.")
                    }
                } else {
                    ForEach(allGaps) { gap in
                        GapCard(gap: gap)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    withAnimation {
                                        gap.isDeleted.toggle()
                                        try? modelContext.save()
                                        refreshEvents()
                                        clockManager.updateTodayHours()
                                    }
                                } label: {
                                    Text(gap.isDeleted ? "Restore" : "Delete")
                                }
                                .tint(gap.isDeleted ? .blue : .red)
                            }
                    }
                }
            } header: {
                Text("Gaps")
            } footer: {
                if !allGaps.isEmpty {
                    Text("Swipe a gap to delete it — that time gets added back to your total. Deleted gaps can be restored the same way.")
                }
            }
        }
        .navigationTitle(date.shortDate)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddEntry = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { refreshEvents() }
        // Clock-in time editor
        .sheet(item: $editingClockIn) { event in
            TimeEditorSheet(title: "Edit Clock In", time: event.clockIn) { newTime in
                event.clockIn = newTime
                try? modelContext.save()
                refreshEvents()
                clockManager.updateTodayHours()
            }
        }
        // Clock-out time editor
        .sheet(item: $editingClockOut) { event in
            TimeEditorSheet(title: "Edit Clock Out", time: event.clockOut ?? Date()) { newTime in
                event.clockOut = newTime
                try? modelContext.save()
                refreshEvents()
                clockManager.updateTodayHours()
            }
        }
        // Add manual entry
        .sheet(isPresented: $showAddEntry) {
            AddEntrySheet(date: date) { clockIn, clockOut in
                let event = ClockEvent(clockIn: clockIn, clockOut: clockOut)
                modelContext.insert(event)
                try? modelContext.save()
                refreshEvents()
                clockManager.updateTodayHours()
            }
        }
    }

    private func refreshEvents() {
        events = clockManager.eventsForDate(date)
    }
}

// MARK: - Time Editor Sheet

struct TimeEditorSheet: View {
    let title: String
    let time: Date
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTime: Date

    init(title: String, time: Date, onSave: @escaping (Date) -> Void) {
        self.title = title
        self.time = time
        self.onSave = onSave
        _selectedTime = State(initialValue: time)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                DatePicker(
                    title,
                    selection: $selectedTime,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()

                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedTime)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Add Entry Sheet

struct AddEntrySheet: View {
    let date: Date
    let onSave: (Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var clockInTime: Date
    @State private var clockOutTime: Date

    private var isValid: Bool {
        clockOutTime > clockInTime
    }

    init(date: Date, onSave: @escaping (Date, Date) -> Void) {
        self.date = date
        self.onSave = onSave

        // Default to 7:00 AM – 5:00 PM on the given date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let defaultIn = calendar.date(byAdding: .hour, value: 7, to: startOfDay) ?? startOfDay
        let defaultOut = calendar.date(byAdding: .hour, value: 17, to: startOfDay) ?? startOfDay

        _clockInTime = State(initialValue: defaultIn)
        _clockOutTime = State(initialValue: defaultOut)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Clock In") {
                    DatePicker(
                        "Start time",
                        selection: $clockInTime,
                        displayedComponents: [.hourAndMinute]
                    )
                }

                Section("Clock Out") {
                    DatePicker(
                        "End time",
                        selection: $clockOutTime,
                        displayedComponents: [.hourAndMinute]
                    )
                }

                if !isValid {
                    Section {
                        Label("Clock out must be after clock in.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(clockInTime, clockOutTime)
                        dismiss()
                    }
                    .bold()
                    .disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - Gap Card

struct GapCard: View {
    @Bindable var gap: GapEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(gap.exitTime.shortTime)
                    Text("–")
                    if let returnTime = gap.returnTime {
                        Text(returnTime.shortTime)
                    } else {
                        Text("Away")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.body.bold())

                Text(gap.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if gap.isDeleted {
                Label("Deleted", systemImage: "arrow.uturn.backward")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1), in: Capsule())
            }
        }
        .opacity(gap.isDeleted ? 0.5 : 1.0)
    }
}
