import SwiftUI

struct SettingsView: View {
    @ObservedObject var timer: TimerManager

    var body: some View {
        Form {
            Section("Idle Detection") {
                HStack {
                    Text("Away timeout")
                    Spacer()
                    Picker("", selection: $timer.awayThresholdMinutes) {
                        Text("2 min").tag(2.0)
                        Text("5 min").tag(5.0)
                        Text("10 min").tag(10.0)
                        Text("15 min").tag(15.0)
                        Text("30 min").tag(30.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 150)
        .navigationTitle("Settings")
    }
}
