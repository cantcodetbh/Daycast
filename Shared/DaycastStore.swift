import Foundation

enum DaycastStore {
    static let suiteName = "H9GD4A7SQF.com.example.daycast.shared"
    static let snapshotKey = "daycast.snapshot"
    private static let snapshotFileName = "DaycastSnapshot.json"

    /// Single channel for cross-process snapshot reads/writes. The shared
    /// app-group container file is the source of truth for both the host app
    /// and the widget extension.
    static func loadSnapshot() -> DaycastSnapshot {
        guard
            let url = snapshotFileURL,
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(DaycastSnapshot.self, from: data)
        else {
            return .unavailable
        }
        return snapshot
    }

    #if DEBUG
    /// Used by the `Tools/RenderDaycastWidget` tool to seed a renderable snapshot
    /// during local development. Not compiled into release builds.
    static func savePreviewSnapshot() {
        save(.preview)
    }
    #endif

    static func save(_ snapshot: DaycastSnapshot) {
        guard
            let url = snapshotFileURL,
            let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }
        try? data.write(to: url, options: [.atomic])
    }

    private static var snapshotFileURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else {
            return nil
        }
        return containerURL.appendingPathComponent(snapshotFileName)
    }
}
