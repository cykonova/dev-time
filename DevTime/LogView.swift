import SwiftUI

struct LogView: View {
    @ObservedObject var timer: TimerManager
    @State private var selectedLogId: UUID?
    @State private var showingAddEntry = false

    private var logsLastMonth: [DayLog] {
        let calendar = Calendar.current
        guard let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) else {
            return timer.appData.logs
        }
        return timer.appData.logs
            .filter { $0.date >= oneMonthAgo }
            .sorted { $0.date > $1.date }
    }

    private var selectedLogDate: Date? {
        guard let id = selectedLogId else { return nil }
        return timer.appData.logs.first { $0.id == id }?.date
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
        } detail: {
            if let logId = selectedLogId,
               let _ = timer.appData.logs.first(where: { $0.id == logId }) {
                DayDetailView(logId: logId, timer: timer) { onSelectLogId in
                    selectedLogId = onSelectLogId
                }
            } else {
                VStack(spacing: 12) {
                    Text("Select a date")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Button {
                        showingAddEntry = true
                    } label: {
                        Label("Add Entry", systemImage: "plus.circle.fill")
                    }
                    .disabled(timer.appData.chargeCodes.isEmpty)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $showingAddEntry) {
                    EntryFormView(timer: timer, logDate: nil, existing: nil) { newLogId in
                        selectedLogId = newLogId
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        .onAppear {
            if selectedLogId == nil {
                selectedLogId = logsLastMonth.first?.id
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

// MARK: - Day Detail View

struct DayDetailView: View {
    let logId: UUID
    @ObservedObject var timer: TimerManager
    var onSelectLog: ((UUID) -> Void)?
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
                    .help("Add entry")
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
                EntryFormView(timer: timer, logDate: log.date, existing: editingEntry) { newLogId in
                    onSelectLog?(newLogId)
                }
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
    let logDate: Date?
    let existing: TimeEntry?
    var onLogCreated: ((UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = Date()
    @State private var selectedChargeCodeId: UUID?
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()

    private var isEditing: Bool { existing != nil }
    private var showDatePicker: Bool { !isEditing }
    private var effectiveDate: Date { isEditing ? (logDate ?? date) : date }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Entry" : "Add Entry")
                .font(.headline)

            Form {
                if showDatePicker {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .onChange(of: date) { _, newDate in
                            startTime = combineDateAndTime(date: newDate, time: startTime)
                            endTime = combineDateAndTime(date: newDate, time: endTime)
                        }
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
                Button(isEditing ? "Save" : "Add") {
                    guard let ccId = selectedChargeCodeId else { return }
                    let start = combineDateAndTime(date: effectiveDate, time: startTime)
                    let end = combineDateAndTime(date: effectiveDate, time: endTime)

                    if let entry = existing {
                        timer.updateEntry(in: effectiveDate, entryId: entry.id, chargeCodeId: ccId, start: start, end: end)
                    } else {
                        timer.insertEntry(into: effectiveDate, chargeCodeId: ccId, start: start, end: end)
                    }
                    if let log = timer.appData.logs.first(where: { Calendar.current.isDate($0.date, inSameDayAs: effectiveDate) }) {
                        onLogCreated?(log.id)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedChargeCodeId == nil || endTime <= startTime)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 350, height: showDatePicker ? 300 : 250)
        .onAppear {
            if let entry = existing {
                selectedChargeCodeId = entry.chargeCodeId
                startTime = entry.startTime
                endTime = entry.endTime ?? Date()
                date = entry.startTime
            } else {
                selectedChargeCodeId = timer.appData.chargeCodes.first?.id
                let baseDate = logDate ?? Date()
                startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate) ?? baseDate
                endTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: baseDate) ?? baseDate
                date = baseDate
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
