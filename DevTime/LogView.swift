import SwiftUI

struct LogView: View {
    @ObservedObject var timer: TimerManager
    @State private var selectedLogId: UUID?
    @State private var showingNewDayEntry = false

    private var logsLastMonth: [DayLog] {
        let calendar = Calendar.current
        guard let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) else {
            return timer.appData.logs
        }
        return timer.appData.logs
            .filter { $0.date >= oneMonthAgo }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationSplitView {
            List(logsLastMonth, selection: $selectedLogId) { log in
                HStack {
                    Text(formatDateShort(log.date))
                        .font(.body)
                    Spacer()
                    Text(formatDecimalHours(log.totalActiveSeconds))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("Time Log")
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItem {
                    Button {
                        showingNewDayEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add entry to a new day")
                    .disabled(timer.appData.chargeCodes.isEmpty)
                }
            }
        } detail: {
            if let logId = selectedLogId,
               let _ = timer.appData.logs.first(where: { $0.id == logId }) {
                DayDetailView(logId: logId, timer: timer)
            } else {
                Text("Select a date")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            if selectedLogId == nil {
                selectedLogId = logsLastMonth.first?.id
            }
        }
        .sheet(isPresented: $showingNewDayEntry) {
            NewDayEntryForm(timer: timer) { newLogId in
                selectedLogId = newLogId
            }
        }
    }

    private func formatDateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        return f.string(from: date)
    }

    private func formatDecimalHours(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        return String(format: "%.1fhrs", hours)
    }
}

// MARK: - New Day Entry Form

struct NewDayEntryForm: View {
    @ObservedObject var timer: TimerManager
    var onCreated: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var selectedChargeCodeId: UUID?
    @State private var startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Entry")
                .font(.headline)

            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .onChange(of: date) { _, newDate in
                        // Keep times on the selected date
                        startTime = combineDateAndTime(date: newDate, time: startTime)
                        endTime = combineDateAndTime(date: newDate, time: endTime)
                    }

                Picker("Task", selection: $selectedChargeCodeId) {
                    Text("Select a task").tag(UUID?.none)
                    ForEach(timer.appData.chargeCodes) { cc in
                        Text("\(cc.name) (\(cc.code))").tag(UUID?.some(cc.id))
                    }
                }

                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    guard let ccId = selectedChargeCodeId else { return }
                    let start = combineDateAndTime(date: date, time: startTime)
                    let end = combineDateAndTime(date: date, time: endTime)
                    timer.insertEntry(into: date, chargeCodeId: ccId, start: start, end: end)
                    // Find the log we just created/updated so we can select it
                    if let log = timer.appData.logs.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                        onCreated(log.id)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedChargeCodeId == nil || endTime <= startTime)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 350, height: 300)
        .onAppear {
            selectedChargeCodeId = timer.appData.chargeCodes.first?.id
        }
    }

    private func combineDateAndTime(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        let dateComps = cal.dateComponents([.year, .month, .day], from: date)
        let timeComps = cal.dateComponents([.hour, .minute, .second], from: time)
        var merged = DateComponents()
        merged.year = dateComps.year
        merged.month = dateComps.month
        merged.day = dateComps.day
        merged.hour = timeComps.hour
        merged.minute = timeComps.minute
        merged.second = timeComps.second
        return cal.date(from: merged) ?? date
    }
}

// MARK: - Day Detail View

struct DayDetailView: View {
    let logId: UUID
    @ObservedObject var timer: TimerManager
    @State private var showingEntryForm = false
    @State private var editingEntry: TimeEntry?
    @State private var entryToDelete: TimeEntry?

    private var log: DayLog? {
        timer.appData.logs.first { $0.id == logId }
    }

    var body: some View {
        if let log {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatDateLong(log.date))
                            .font(.title2.bold())
                        Text("Total: \(formatDecimalHours(log.totalActiveSeconds))")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        editingEntry = nil
                        showingEntryForm = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("Add entry to this day")
                    .disabled(timer.appData.chargeCodes.isEmpty)
                }
                .padding()

                Divider()

                // Entries table
                if log.entries.isEmpty {
                    Text("No entries for this day.")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Column header
                        HStack {
                            Text("Task")
                                .fontWeight(.semibold)
                                .frame(minWidth: 120, alignment: .leading)
                            Text("Charge Code")
                                .fontWeight(.semibold)
                                .frame(minWidth: 80, alignment: .leading)
                            Spacer()
                            Text("Start")
                                .fontWeight(.semibold)
                                .frame(width: 70, alignment: .trailing)
                            Text("End")
                                .fontWeight(.semibold)
                                .frame(width: 70, alignment: .trailing)
                            Text("Hours")
                                .fontWeight(.semibold)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ForEach(log.entries) { entry in
                            let chargeCode = timer.appData.chargeCodes.first { $0.id == entry.chargeCodeId }
                            HStack {
                                Text(chargeCode?.name ?? "Unknown")
                                    .frame(minWidth: 120, alignment: .leading)
                                Text(chargeCode?.code ?? "-")
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 80, alignment: .leading)
                                Spacer()
                                Text(formatTimeOfDay(entry.startTime))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 70, alignment: .trailing)
                                Text(formatTimeOfDay(entry.endTime ?? Date()))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 70, alignment: .trailing)
                                Text(formatDecimalHours(entry.activeSeconds))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .font(.body)
                            .contextMenu {
                                Button("Edit") {
                                    editingEntry = entry
                                    showingEntryForm = true
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    entryToDelete = entry
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingEntryForm) {
                EntryFormView(timer: timer, logDate: log.date, existing: editingEntry)
            }
            .alert("Delete Entry?", isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { entryToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let entry = entryToDelete {
                        timer.deleteEntry(from: log.date, entryId: entry.id)
                    }
                    entryToDelete = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
        } else {
            Text("Log not found")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func formatDateLong(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: date)
    }

    private func formatTimeOfDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatDecimalHours(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        return String(format: "%.1fhrs", hours)
    }
}

// MARK: - Entry Form (Insert / Edit)

struct EntryFormView: View {
    @ObservedObject var timer: TimerManager
    let logDate: Date
    let existing: TimeEntry?

    @Environment(\.dismiss) private var dismiss

    @State private var selectedChargeCodeId: UUID?
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()

    private var isEditing: Bool { existing != nil }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Entry" : "Add Entry")
                .font(.headline)

            Form {
                Picker("Task", selection: $selectedChargeCodeId) {
                    Text("Select a task").tag(UUID?.none)
                    ForEach(timer.appData.chargeCodes) { cc in
                        Text("\(cc.name) (\(cc.code))").tag(UUID?.some(cc.id))
                    }
                }

                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Add") {
                    guard let ccId = selectedChargeCodeId else { return }
                    let start = combineDateAndTime(date: logDate, time: startTime)
                    let end = combineDateAndTime(date: logDate, time: endTime)

                    if let entry = existing {
                        timer.updateEntry(in: logDate, entryId: entry.id, chargeCodeId: ccId, start: start, end: end)
                    } else {
                        timer.insertEntry(into: logDate, chargeCodeId: ccId, start: start, end: end)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedChargeCodeId == nil || endTime <= startTime)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 350, height: 250)
        .onAppear {
            if let entry = existing {
                selectedChargeCodeId = entry.chargeCodeId
                startTime = entry.startTime
                endTime = entry.endTime ?? Date()
            } else {
                selectedChargeCodeId = timer.appData.chargeCodes.first?.id
                // Default to 9am-5pm on the log date
                startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: logDate) ?? logDate
                endTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: logDate) ?? logDate
            }
        }
    }

    private func combineDateAndTime(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        let dateComps = cal.dateComponents([.year, .month, .day], from: date)
        let timeComps = cal.dateComponents([.hour, .minute, .second], from: time)
        var merged = DateComponents()
        merged.year = dateComps.year
        merged.month = dateComps.month
        merged.day = dateComps.day
        merged.hour = timeComps.hour
        merged.minute = timeComps.minute
        merged.second = timeComps.second
        return cal.date(from: merged) ?? date
    }
}
