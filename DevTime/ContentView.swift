import SwiftUI

struct ContentView: View {
    @ObservedObject var timer: TimerManager
    @State private var newCodeName = ""
    @State private var newCodeValue = ""
    @State private var showingAddCode = false
    @State private var logWindow: NSWindow?
    @State private var settingsWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(timer.emoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text("DevTime")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(timer.isTracking ? .green : .gray)
                            .frame(width: 7, height: 7)
                        Text(timer.isTracking ? "Tracking" : "Idle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(formatTime(timer.todayTotalSeconds))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Active timer card
            if timer.isTracking, let codeId = timer.activeChargeCodeId {
                let code = timer.appData.chargeCodes.first { $0.id == codeId }
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(code?.name ?? "Unknown")
                                .font(.headline)
                            Text(code?.code ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(timer.clockString)
                            .font(.system(.title2, design: .monospaced).bold())
                            .foregroundStyle(.green)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(progressColor)
                                .frame(width: progressWidth(in: geo.size.width), height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Button {
                            timer.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Task list
            VStack(spacing: 0) {
                HStack {
                    Text("Tasks")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showingAddCode.toggle()
                    } label: {
                        Image(systemName: showingAddCode ? "xmark.circle.fill" : "plus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

                if showingAddCode {
                    VStack(spacing: 6) {
                        TextField("Task name", text: $newCodeName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Charge code", text: $newCodeValue)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Add") {
                                guard !newCodeName.isEmpty, !newCodeValue.isEmpty else { return }
                                timer.addChargeCode(name: newCodeName, code: newCodeValue)
                                newCodeName = ""
                                newCodeValue = ""
                                showingAddCode = false
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(newCodeName.isEmpty || newCodeValue.isEmpty)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                if timer.appData.chargeCodes.isEmpty {
                    Text("No tasks yet. Tap + to add one.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 2) {
                        ForEach(timer.appData.chargeCodes) { code in
                            let isActive = timer.isTracking && timer.activeChargeCodeId == code.id
                            Button {
                                if timer.isTracking {
                                    if timer.activeChargeCodeId == code.id {
                                        timer.stop()
                                    } else {
                                        timer.switchTask(to: code.id)
                                    }
                                } else {
                                    timer.start(chargeCodeId: code.id)
                                }
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(isActive ? .green : .clear)
                                        .overlay(
                                            Circle().stroke(Color.secondary.opacity(0.3), lineWidth: isActive ? 0 : 1)
                                        )
                                        .frame(width: 8, height: 8)
                                    Text(code.name)
                                        .font(.body)
                                    Spacer()
                                    Text(code.code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    // Delete button (only when not tracking this task)
                                    if !isActive {
                                        Button {
                                            timer.removeChargeCode(code.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption2)
                                                .foregroundStyle(.red.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isActive ? Color.green.opacity(0.1) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 12)

            // Bottom bar - Settings, View Log, Quit
            HStack {
                Button {
                    openSettingsWindow()
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    openLogWindow()
                } label: {
                    Label("Time Log", systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    timer.saveCurrentState()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
    }

    // MARK: - Progress helpers

    private var progressColor: Color {
        let hours = timer.todayTotalSeconds / 3600
        if hours < 4 { return .green }
        if hours < 8 { return .yellow }
        if hours < 10 { return .orange }
        return .red
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        let hours = timer.todayTotalSeconds / 3600
        let fraction = min(hours / 12.0, 1.0)
        return totalWidth * fraction
    }

    // MARK: - Windows

    private func openLogWindow() {
        if let existing = logWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = LogView(timer: timer)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "DevTime - Time Log"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 720, height: 450))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logWindow = window
    }

    private func openSettingsWindow() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(timer: timer)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "DevTime - Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 350, height: 150))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
