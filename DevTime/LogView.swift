import SwiftUI

struct LogView: View {
    @ObservedObject var timer: TimerManager
    @State private var selectedLogId: UUID?

    private var logsLastMonth: [DayLog] {
        let calendar = Calendar.current
        guard let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) else {
            return timer.appData.logs
        }
        return timer.appData.logs
            .filter { $0.date >= oneMonthAgo }
            .sorted { $0.date > $1.date }
    }

    private var selectedLog: DayLog? {
        guard let id = selectedLogId else { return nil }
        return logsLastMonth.first { $0.id == id }
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
            if let log = selectedLog {
                DayDetailView(log: log, timer: timer)
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

struct DayDetailView: View {
    let log: DayLog
    @ObservedObject var timer: TimerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDateLong(log.date))
                    .font(.title2.bold())
                Text("Total: \(formatDecimalHours(log.totalActiveSeconds))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
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
                    }
                }
            }
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
