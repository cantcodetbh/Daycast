import Foundation

/// Identifiers shared between the host app, the widget extension, and the
/// login helper. Keeping these in one place avoids drift between the Info.plist
/// `BGTaskSchedulerPermittedIdentifiers` entry, the widget kind string used by
/// `WidgetCenter`, and the bundle identifiers referenced by `SMAppService` and
/// `NSWorkspace`.
enum DaycastConstants {
    /// Stable widget kind. Must match the value used by `WidgetCenter` calls
    /// in the host app.
    static let widgetKind = "DaycastExtraLargeWidget"

    /// Background app refresh task identifier. Must also be listed in
    /// `Daycast/Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.
    static let backgroundRefreshTaskIdentifier = "com.example.daycast.refresh"

    /// Bundle identifier of the main host app.
    static let mainAppBundleIdentifier = "com.example.daycast"

    /// Bundle identifier of the login item that lives inside
    /// `Daycast.app/Contents/Library/LoginItems/`.
    static let loginHelperBundleIdentifier = "com.example.daycast.loginhelper"
}
