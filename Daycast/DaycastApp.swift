import AppKit
import BackgroundTasks
import CoreLocation
import EventKit
import os
import ServiceManagement
import SwiftUI
import WidgetKit

@main
struct DaycastApp: App {
    @NSApplicationDelegateAdaptor(DaycastAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(syncEngine: appDelegate.syncEngine)
                .frame(minWidth: 420, minHeight: 320)
        }
    }
}

@MainActor
final class DaycastAppDelegate: NSObject, NSApplicationDelegate {
    let syncEngine = DaycastSyncEngine()

    /// Structured logger for background-sync lifecycle warnings. The
    /// subsystem matches `CFBundleIdentifier` so messages show up in
    /// Console.app and `log show` with proper metadata, can be filtered
    /// and redacted independently of other subsystems, and respect the
    /// user's "private" data toggles in Console.
    private static let log = Logger(subsystem: DaycastConstants.mainAppBundleIdentifier, category: "background-sync")

    #if !os(macOS)
    private static var didRegisterBackgroundTask = false
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tell the system not to auto-terminate us. Without this, macOS will
        // kill the process when it decides the app is "idle" (no visible
        // windows, no recent user activity), which means the in-app Timer
        // that refreshes the widget stops firing. The reason string is
        // surfaced in `log show` so it's clear *why* the app is still alive.
        //
        // The return value is `Bool` on iOS (false = system denied) and `Void`
        // on macOS (the macOS SDK signature is fire-and-forget). We can only
        // detect a denial on iOS — on macOS, if the call doesn't take, you'll
        // see the process get killed at idle and have to dig through
        // `log show` to figure out why.
        #if os(iOS)
        let didDisable = ProcessInfo.processInfo.disableAutomaticTermination(Self.backgroundTerminationReason)
        if !didDisable {
            Self.log.error("disableAutomaticTermination was rejected by the system; background sync may be killed at any time.")
        }
        #else
        ProcessInfo.processInfo.disableAutomaticTermination(Self.backgroundTerminationReason)
        #endif

        #if !os(macOS)
        // `BGTaskScheduler.register` must be called before this method
        // returns, and only once per process — calling it twice with the same
        // identifier crashes. The flag keeps us safe if the delegate is
        // re-entered (e.g. the user reopens the app while it's still alive).
        if !Self.didRegisterBackgroundTask {
            Self.didRegisterBackgroundTask = true

            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: DaycastConstants.backgroundRefreshTaskIdentifier,
                using: nil
            ) { [weak self] task in
                self?.syncEngine.handleBackgroundRefresh(task)
            }
        }

        DaycastSyncEngine.scheduleBackgroundRefresh()
        #endif
        syncEngine.startInAppSync()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProcessInfo.processInfo.enableAutomaticTermination(Self.backgroundTerminationReason)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Reason string shared by the disable/enable Automatic Termination calls
    /// so Activity Monitor and `log show` show the same identifier for both.
    /// Matched deliberately — the system doesn't require the strings to agree
    /// but it makes correlating the two calls trivial when debugging.
    private static let backgroundTerminationReason = "Daycast syncs the widget in the background"
}

@MainActor
final class DaycastSyncEngine: ObservableObject {
    @Published var status = "Ready to add the Daycast widget."
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginDetail = "Checking login item."
    @Published var currentSnapshot = DaycastStore.loadSnapshot()

    private let loginItemService = SMAppService.loginItem(identifier: DaycastConstants.loginHelperBundleIdentifier)
    private let launchAtLoginDefaultKey = "DaycastDidSetLaunchAtLoginDefault"
    private let eventStore = EKEventStore()
    private let locationProvider = DaycastLocationProvider()
    private var syncTimer: DispatchSourceTimer?
    private var calendarChangeObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?

    /// How often the in-app timer fires to refresh the widget data. On macOS
    /// this is the *primary* sync cadence — `BGTaskScheduler` is iOS-only,
    /// so the only way to keep the widget fresh when the user isn't actively
    /// using the app is to keep the app alive in the background and poll on
    /// a tight interval. Bump to 1 min for aggressive freshness, 15+ min for
    /// battery savings.
    private static let inAppRefreshInterval: TimeInterval = 5 * 60

    /// Structured logger for background-sync lifecycle warnings. Same
    /// subsystem/category as the delegate's logger so all background-sync
    /// diagnostics land in the same Console.app bucket.
    private static let log = Logger(subsystem: DaycastConstants.mainAppBundleIdentifier, category: "background-sync")

    init() {
        configureLaunchAtLoginDefault()
    }

    deinit {
        // Defensive: the engine lives for the app's lifetime so this is
        // effectively dead code in production, but if the engine is ever
        // recreated (tests, future refactor) cancelling the timer prevents
        // a dangling event handler from firing into a deallocated `self`.
        syncTimer?.cancel()
    }

    // MARK: - Public UI hooks

    func prepareForSettingsWindow() {
        currentSnapshot = DaycastStore.loadSnapshot()

        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            status = "Asking for Calendar access."
            requestCalendarAccess()
        }
    }

    func requestCalendarAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, _ in
                Task { @MainActor in
                    self?.handleCalendarAuthorization(granted: granted)
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.handleCalendarAuthorization(granted: granted)
                }
            }
        }
    }

    func manualSync() {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            requestCalendarAccess()
            return
        }
        syncNow(reason: "Manual sync.")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = activeLoginService()

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }

            refreshLaunchAtLoginStatus()

            if activeLoginService().status != .notRegistered {
                UserDefaults.standard.set(true, forKey: launchAtLoginDefaultKey)
            }
        } catch {
            refreshLaunchAtLoginStatus()
            launchAtLoginDetail = "macOS could not update Login Items: \(error.localizedDescription)"
        }
    }

    func refreshLaunchAtLoginStatus() {
        switch activeLoginService().status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginDetail = "Daycast will start quietly when you log in."
            UserDefaults.standard.set("enabled", forKey: "DaycastLaunchAtLoginStatus")
        case .requiresApproval:
            launchAtLoginEnabled = false
            launchAtLoginDetail = "Approve Daycast in System Settings > General > Login Items."
            UserDefaults.standard.set("requiresApproval", forKey: "DaycastLaunchAtLoginStatus")
        case .notRegistered:
            launchAtLoginEnabled = false
            launchAtLoginDetail = "Daycast will only sync after it has been opened."
            UserDefaults.standard.set("notRegistered", forKey: "DaycastLaunchAtLoginStatus")
        case .notFound:
            launchAtLoginEnabled = false
            launchAtLoginDetail = "Login item is unavailable for this build."
            UserDefaults.standard.set("notFound", forKey: "DaycastLaunchAtLoginStatus")
        @unknown default:
            launchAtLoginEnabled = false
            launchAtLoginDetail = "macOS returned an unknown Login Items state."
            UserDefaults.standard.set("unknown", forKey: "DaycastLaunchAtLoginStatus")
        }

        UserDefaults.standard.set(launchAtLoginDetail, forKey: "DaycastLaunchAtLoginDetail")
    }

    // MARK: - Background task plumbing
    //
    // `BGTaskScheduler` and the `BGTask` / `BGAppRefreshTask` types are
    // unavailable on macOS — they're iOS, tvOS, and watchOS only. On macOS
    // the auto-sync story falls back to the in-app 15-minute timer, the
    // `EKEventStoreChanged` observer (while the app is open), and the
    // `DaycastLoginHelper` login item (which launches the app at login so
    // the timer can run). That's the best we can do without a macOS
    // equivalent of `BGAppRefreshTask`.

    /// Submit the next BG refresh request to the system. Safe to call from
    /// the main thread or from a background context. No-op on macOS.
    static func scheduleBackgroundRefresh() {
        #if !os(macOS)
        let request = BGAppRefreshTaskRequest(identifier: DaycastConstants.backgroundRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission can fail if the identifier isn't in Info.plist, if
            // the system is throttling us, or if we're being run in a context
            // that doesn't permit BG scheduling. We log and move on; the
            // in-app timer is a backstop. The error is marked `.public` so
            // it shows up in `log show` output without needing `--info`.
            Self.log.error("Failed to schedule BG refresh: \(error, privacy: .public)")
        }
        #endif
    }

    #if !os(macOS)
    /// Handler invoked by `BGTaskScheduler` when the OS wakes us to do
    /// background work. Reschedules the next request first so a failure
    /// here doesn't permanently break the cadence, then runs the same sync
    /// path the in-app timer uses.
    func handleBackgroundRefresh(_ task: BGTask) {
        Self.scheduleBackgroundRefresh()

        // Set the expiration handler up front so we never race against the
        // OS killing us before the work task has been spawned. The closure
        // captures `detachedWork` by reference, so the assignment below
        // propagates.
        var detachedWork: Task<Void, Never>?
        task.expirationHandler = {
            detachedWork?.cancel()
        }

        // We need MainActor-isolated state (eventStore, locationProvider) to
        // pass into the detached work task. Hop to the main actor briefly to
        // capture it, then jump back to a detached task to do the heavy
        // calendar/network work off the main thread.
        Task { @MainActor [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            let previous = self.currentSnapshot
            let eventStore = self.eventStore
            let locationProvider = self.locationProvider

            detachedWork = Task.detached(priority: .utility) { [weak self] in
                let result = await DaycastSyncEngine.performBackgroundSync(
                    previous: previous,
                    eventStore: eventStore,
                    locationProvider: locationProvider,
                    interimSnapshotHandler: { [weak self] snapshot in
                        guard let engine = self else { return }
                        await MainActor.run {
                            engine.saveAndReload(snapshot)
                        }
                    }
                )
                guard let engine = self else {
                    task.setTaskCompleted(success: false)
                    return
                }
                await MainActor.run {
                    engine.applyBackgroundSyncResult(result)
                    task.setTaskCompleted(success: result.didSync)
                }
            }
        }
    }
    #endif

    // MARK: - In-app sync

    /// Starts the in-app refresh timer and the `EKEventStoreChanged` observer.
    /// On macOS this is the only sync path that fires while the app is
    /// running in the background (LSUIElement app, no dock icon).
    ///
    /// Uses `DispatchSourceTimer` on a global dispatch queue rather than
    /// `Timer` on the main `RunLoop`, because a LSUIElement app with no
    /// visible windows can stall the main `RunLoop`'s event servicing and
    /// the `Timer` won't fire. The dispatch source is independent of the
    /// main thread and fires reliably in the background.
    func startInAppSync() {
        syncTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + Self.inAppRefreshInterval, repeating: Self.inAppRefreshInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.syncNow(reason: "Background refresh.")
            }
        }
        timer.resume()
        syncTimer = timer

        calendarChangeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleDebouncedSync(reason: "Calendar changed.")
            }
        }

        syncNow(reason: "Background sync started.")
    }

    // MARK: - Sync orchestration

    private func configureLaunchAtLoginDefault() {
        refreshLaunchAtLoginStatus()
        guard !UserDefaults.standard.bool(forKey: launchAtLoginDefaultKey) else { return }
        if activeLoginService().status == .notRegistered {
            setLaunchAtLogin(true)
        } else {
            UserDefaults.standard.set(true, forKey: launchAtLoginDefaultKey)
        }
    }

    private func activeLoginService() -> SMAppService {
        loginItemService.status == .notFound ? .mainApp : loginItemService
    }

    private func handleCalendarAuthorization(granted: Bool) {
        status = granted ? "Calendar access granted. Syncing widget." : "Calendar access was not granted."

        if granted {
            syncNow(reason: "Calendar access granted.")
        }
    }

    private func scheduleDebouncedSync(reason: String) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                self?.syncNow(reason: reason)
            }
        }
    }

    private func syncNow(reason: String) {
        let authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        guard hasCalendarAccess(authorizationStatus) else {
            status = authorizationStatus == .notDetermined
                ? "Calendar access is needed for automatic sync."
                : "Calendar access is off. Enable it in System Settings."
            return
        }

        guard syncTask == nil else { return }

        status = "\(reason) Syncing calendar and weather."
        // Snapshot MainActor state and hop off to a detached task so the
        // synchronous `EKEventStore.events(matching:)` call doesn't block the
        // main thread.
        let previousSnapshot = currentSnapshot
        let eventStore = self.eventStore
        let locationProvider = self.locationProvider

        syncTask = Task.detached(priority: .utility) { [weak self] in
            let result = await DaycastSyncEngine.performBackgroundSync(
                previous: previousSnapshot,
                eventStore: eventStore,
                locationProvider: locationProvider,
                interimSnapshotHandler: { [weak self] snapshot in
                    guard let engine = self else { return }
                    await MainActor.run {
                        engine.saveAndReload(snapshot)
                    }
                }
            )
            guard let engine = self else { return }
            await MainActor.run {
                engine.applyInAppSyncResult(result, reason: reason)
                engine.syncTask = nil
            }
        }
    }

    private func applyInAppSyncResult(_ result: SyncOutcome, reason: String) {
        saveAndReload(result.snapshot)
        status = result.statusMessage(reason: reason)
        Self.scheduleBackgroundRefresh()
    }

    private func applyBackgroundSyncResult(_ result: SyncOutcome) {
        // No UI status updates here — this may be running with no window open.
        saveAndReload(result.snapshot)
    }

    // MARK: - Background-safe sync work

    /// Outcome of a sync attempt. Carries the snapshot that should be saved
    /// and reloaded into widgets, plus enough metadata to render a useful
    /// status message in the in-app UI.
    private struct SyncOutcome {
        let snapshot: DaycastSnapshot
        let didSync: Bool
        let weatherFailed: Bool
        let usedFallbackLocation: Bool

        func statusMessage(reason: String) -> String {
            if !weatherFailed {
                return "Widget synced: \(snapshot.today.events.count) today, \(snapshot.tomorrow.events.count) tomorrow, \(snapshot.today.weather.condition.lowercased()) now."
            } else if usedFallbackLocation {
                return "Widget synced using Wakefield weather. Enable Location for local weather."
            } else {
                return "Calendar synced. Weather needs Location access or network."
            }
        }
    }

    /// Calendar + weather work, safe to call from a detached background task.
    /// `EKEventStore` is thread-safe; `DaycastLocationProvider` is `@MainActor`
    /// but its public API hops back to the main actor internally.
    nonisolated private static func performBackgroundSync(
        previous: DaycastSnapshot,
        eventStore: EKEventStore,
        locationProvider: DaycastLocationProvider,
        interimSnapshotHandler: @escaping @Sendable (DaycastSnapshot) async -> Void
    ) async -> SyncOutcome {
        let calendarSnapshot = makeCalendarSnapshot(previous: previous, eventStore: eventStore)
        // Persist calendar as we go so the widget always has *something*,
        // even if the weather fetch fails.
        DaycastStore.save(calendarSnapshot)
        await interimSnapshotHandler(calendarSnapshot)

        do {
            let weather = try await fetchWeather(locationProvider: locationProvider)
            let withWeather = calendarSnapshot.applying(todayWeather: weather.today, tomorrowWeather: weather.tomorrow)
            return SyncOutcome(snapshot: withWeather, didSync: true, weatherFailed: false, usedFallbackLocation: false)
        } catch {
            // First fallback: try the Wakefield hard-coded location so the
            // widget at least has plausible numbers to show.
            do {
                let weather = try await DaycastWeatherService.fetchWeather(for: .daycastFallback)
                let withWeather = calendarSnapshot.applying(todayWeather: weather.today, tomorrowWeather: weather.tomorrow)
                return SyncOutcome(snapshot: withWeather, didSync: true, weatherFailed: true, usedFallbackLocation: true)
            } catch {
                // Second fallback: keep whatever weather we had last time.
                let reused = calendarSnapshot.applying(
                    todayWeather: previous.today.weather,
                    tomorrowWeather: previous.tomorrow.weather
                )
                return SyncOutcome(snapshot: reused, didSync: true, weatherFailed: true, usedFallbackLocation: false)
            }
        }
    }

    nonisolated private static func fetchWeather(locationProvider: DaycastLocationProvider) async throws -> DaycastWeatherPair {
        let location = try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask {
                try await locationProvider.currentLocation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(12))
                throw CLError(.locationUnknown)
            }

            guard let location = try await group.next() else {
                throw CLError(.locationUnknown)
            }
            group.cancelAll()
            return location
        }
        return try await DaycastWeatherService.fetchWeather(for: location)
    }

    nonisolated private static func makeCalendarSnapshot(previous: DaycastSnapshot, eventStore: EKEventStore) -> DaycastSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: todayStart) ?? tomorrowStart
        let todayEvents = events(eventStore: eventStore, start: todayStart, end: tomorrowStart)
        let tomorrowEvents = events(eventStore: eventStore, start: tomorrowStart, end: dayAfterTomorrow)

        return DaycastSnapshot(
            today: DaycastDay(
                label: "Today",
                dateLine: formattedDateLine(todayStart),
                weather: previous.today.weather,
                events: todayEvents,
                focusWindow: focusWindow(for: todayEvents, fallback: "Open day"),
                nudge: nudge(for: todayEvents, fallback: "You have space to breathe today")
            ),
            tomorrow: DaycastDay(
                label: "Tomorrow",
                dateLine: formattedDateLine(tomorrowStart),
                weather: previous.tomorrow.weather,
                events: tomorrowEvents,
                focusWindow: focusWindow(for: tomorrowEvents, fallback: "Open day"),
                nudge: nudge(for: tomorrowEvents, fallback: "Tomorrow is clear so far")
            )
        )
    }

    nonisolated private static func events(eventStore: EKEventStore, start: Date, end: Date) -> [DaycastEvent] {
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)

        return eventStore.events(matching: predicate)
            .sorted { first, second in
                if first.isAllDay != second.isAllDay {
                    return first.isAllDay && !second.isAllDay
                }

                return first.startDate < second.startDate
            }
            .prefix(8)
            .map { event in
                DaycastEvent(
                    title: event.title ?? "Untitled event",
                    time: event.isAllDay ? "All day" : formattedTime(event.startDate),
                    location: event.location,
                    isAllDay: event.isAllDay
                )
            }
    }

    nonisolated private static func nudge(for events: [DaycastEvent], fallback: String) -> String {
        guard let first = events.first else {
            return fallback
        }

        if first.isAllDay {
            return "\(first.title) is all day"
        }

        return "Starts at \(first.time) with \(first.title)"
    }

    nonisolated private static func focusWindow(for events: [DaycastEvent], fallback: String) -> String {
        let timedEvents = events.filter { !$0.isAllDay }

        guard let last = timedEvents.last else {
            return fallback
        }

        return "Free after \(last.time)"
    }

    // MARK: - Helpers

    private func hasCalendarAccess(_ authorizationStatus: EKAuthorizationStatus) -> Bool {
        authorizationStatus == .fullAccess
    }

    private func saveAndReload(_ snapshot: DaycastSnapshot) {
        DaycastStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        currentSnapshot = snapshot
    }

    nonisolated private static func formattedTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    nonisolated private static func formattedDateLine(_ date: Date) -> String {
        dateLineFormatter.string(from: date)
    }

    nonisolated private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    nonisolated private static let dateLineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()
}
