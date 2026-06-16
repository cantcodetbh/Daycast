import AppKit
import SwiftUI

@main
struct DaycastLoginHelperApp: App {
    @NSApplicationDelegateAdaptor(LoginHelperDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class LoginHelperDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The login helper is a convenience launcher. The actual widget
        // refreshes happen via the host app's sync engine.
        launchMainApp()
    }

    private func launchMainApp() {
        guard let mainAppURL = bundledMainAppURL() ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.example.daycast") else {
            NSApp.terminate(nil)
            return
        }

        NSWorkspace.shared.openApplication(
            at: mainAppURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in
            NSApp.terminate(nil)
        }
    }

    private func bundledMainAppURL() -> URL? {
        let helperURL = Bundle.main.bundleURL
        let mainAppURL = helperURL
            .deletingLastPathComponent() // LoginItems
            .deletingLastPathComponent() // Library
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // Daycast.app

        guard mainAppURL.pathExtension == "app" else {
            return nil
        }

        return mainAppURL
    }
}
