import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var syncEngine: DaycastSyncEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Daycast")
                    .font(.largeTitle.bold())
                Text("A Today + Tomorrow calendar and weather widget for your Mac.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Syncs calendar and weather in the background", systemImage: "arrow.triangle.2.circlepath")
                Label("Keeps the widget updated after this window closes", systemImage: "macwindow.on.rectangle")
                Label("Starts at login so the widget keeps updating after restart", systemImage: "power")
                Label("Uses this window for permissions and settings", systemImage: "slider.horizontal.3")
            }
            .font(.body)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { syncEngine.launchAtLoginEnabled },
                    set: { syncEngine.setLaunchAtLogin($0) }
                )) {
                    Label("Start Daycast at Login", systemImage: "person.crop.circle.badge.clock")
                }

                Text(syncEngine.launchAtLoginDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Login Items", systemImage: "gearshape")
                }
            }

            HStack {
                Button {
                    syncEngine.manualSync()
                } label: {
                    Label("Sync Now", systemImage: "arrow.clockwise")
                }

                Button {
                    syncEngine.requestCalendarAccess()
                } label: {
                    Label("Allow Calendar", systemImage: "checkmark.shield")
                }
            }

            Text(syncEngine.status)
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Synced Data")
                    .font(.headline)
                Text("Today: \(syncEngine.currentSnapshot.today.events.count) events")
                Text("Tomorrow: \(syncEngine.currentSnapshot.tomorrow.events.count) events")
                Text("Weather: \(syncEngine.currentSnapshot.today.weather.condition), \(syncEngine.currentSnapshot.today.weather.temperature)°")
                if let firstTomorrow = syncEngine.currentSnapshot.tomorrow.events.first {
                    Text("Next tomorrow: \(firstTomorrow.time) \(firstTomorrow.title)")
                        .lineLimit(1)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .onAppear {
            syncEngine.refreshLaunchAtLoginStatus()
            syncEngine.prepareForSettingsWindow()
        }
    }
}
