import AppKit
import CoreLocation
import Foundation
import Observation
import ServiceManagement
import UniformTypeIdentifiers

/// App state: today's/tomorrow's times, the menu bar state, and the ticking clock.
@Observable
final class PrayerStore {
    let settings = AppSettings()

    private(set) var now = Date()
    private(set) var today: [PrayerTime] = []
    private(set) var tomorrow: [PrayerTime] = []
    private(set) var state: MenuBarState?
    private(set) var isAdhanPlaying = false
    private(set) var locationStatus: String?
    private(set) var adhanStatus: String?
    private(set) var notificationsDenied = false
    var showingSettings = false

    /// Time simulator (debug): simulated now = real now + offset. 0 = real time. Not persisted.
    private(set) var timeOffset: TimeInterval = 0
    var isSimulating: Bool { timeOffset != 0 }

    /// The app's "now" — always use this instead of `Date()`.
    private func currentDate() -> Date { Date().addingTimeInterval(timeOffset) }

    func simulate(_ date: Date) {
        timeOffset = date.timeIntervalSince(Date())
        lastAdhanPrayer = nil
        recalculate()
    }

    /// Jumps to `seconds` before the next prayer (e.g. 605 → countdown kicks in 5 s later).
    func simulateBeforeNextPrayer(seconds: TimeInterval) {
        let prayers = (today + tomorrow).filter { $0.name.isPrayer }
        guard let next = prayers.first(where: { $0.date > now.addingTimeInterval(seconds) }) ?? prayers.last else { return }
        simulate(next.date.addingTimeInterval(-seconds))
    }

    func resetSimulation() {
        timeOffset = 0
        stopAdhan()
        recalculate()
    }

    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    @ObservationIgnored private let location = LocationService()
    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private let adhan = AdhanPlayer()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var computedDay: Date?
    @ObservationIgnored private var lastAdhanPrayer: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        location.onUpdate = { [weak self] in self?.locationUpdated($0) }
        location.onError = { [weak self] in self?.locationStatus = $0 }
        adhan.onFinish = { [weak self] in self?.isAdhanPlaying = false }

        Task {
            await notifications.requestAuthorization()
            await refreshNotificationStatus()
        }
        observeSystemEvents()
        recalculate()

        if settings.locationMode == .automatic {
            location.requestLocation()
        }
    }

    // MARK: Menu bar

    var menuBarTitle: String {
        (isSimulating ? "🧪 " : "") + stateTitle
    }

    private var stateTitle: String {
        switch state {
        case .idle(let next): "\(next.title) \(Fmt.hoursMinutes(next.date.timeIntervalSince(now)))"
        case .approaching(let next): "🟠 \(next.title) \(Fmt.minutesSeconds(next.date.timeIntervalSince(now)))"
        case .active(let current): "🟢 " + String(localized: "\(current.title) · now")
        case nil: "Must Salah"
        }
    }

    /// Icon of the prayer the menu bar is about: the next one while counting down, the current one while active.
    var menuBarIcon: String {
        switch state {
        case .idle(let next), .approaching(let next): next.name.icon
        case .active(let current): current.name.icon
        case nil: "moon.stars.fill"
        }
    }

    /// After Isya's active window, the panel shows tomorrow's times.
    var displayedTimes: (label: String, times: [PrayerTime]) {
        if let isya = today.last, now.timeIntervalSince(isya.date) >= MenuBarState.activeWindow {
            return (String(localized: "Tomorrow"), tomorrow)
        }
        return (String(localized: "Today"), today)
    }

    // MARK: Calculation & ticking

    func recalculate() {
        let now = currentDate()
        let coordinate = settings.coordinate
        let offsets = settings.offsets
        today = PrayerCalculator.times(for: now, coordinate: coordinate, offsets: offsets)
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        tomorrow = PrayerCalculator.times(for: tomorrowDate, coordinate: coordinate, offsets: offsets)
        computedDay = now
        rescheduleNotifications()
        tick()
    }

    func refreshNotificationStatus() async {
        notificationsDenied = await notifications.isDenied()
    }

    /// Switches the app language (writes the app-only AppleLanguages override) and relaunches,
    /// since Bundle localizations are fixed for the lifetime of the process.
    func setLanguage(_ language: AppLanguage) {
        guard language != settings.language else { return }
        settings.language = language
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        relaunch()
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    func rescheduleNotifications() {
        notifications.reschedule(
            prayers: today + tomorrow,
            enabled: settings.notifyPrayers,
            adhanWillPlay: settings.adhanEnabled && settings.adhanURL != nil,
            now: currentDate(),
            timeOffset: timeOffset
        )
    }

    private func tick() {
        let now = currentDate()
        if let computedDay, !Calendar.current.isDate(computedDay, inSameDayAs: now) {
            recalculate()
            return
        }
        self.now = now
        state = MenuBarState.compute(now: now, prayers: (today + tomorrow).filter { $0.name.isPrayer })
        playAdhanIfNeeded(now: now)
        scheduleNextTick(after: now)
    }

    /// Every second while approaching; otherwise on the next whole minute
    /// (prayer times are whole minutes, so state changes always land on one).
    private func scheduleNextTick(after now: Date) {
        timer?.invalidate()
        let t = now.timeIntervalSinceReferenceDate
        let fireDate: Date
        if case .approaching = state {
            fireDate = Date(timeIntervalSinceReferenceDate: t.rounded(.down) + 1)
        } else {
            fireDate = Date(timeIntervalSinceReferenceDate: ((t / 60).rounded(.down) + 1) * 60)
        }
        // fireDate is in (possibly simulated) app time; the Timer needs real time.
        let timer = Timer(fire: fireDate.addingTimeInterval(-timeOffset), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observeSystemEvents() {
        let recalc: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.recalculate() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: recalc))
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: recalc))
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: recalc))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: recalc))
    }

    // MARK: Adhan

    private func playAdhanIfNeeded(now: Date) {
        guard settings.adhanEnabled,
              let url = settings.adhanURL,
              let current = state?.active,
              settings.notifyPrayers.contains(current.name),
              now.timeIntervalSince(current.date) < 60, // don't play late, e.g. after waking from sleep
              lastAdhanPrayer != current.date
        else { return }
        lastAdhanPrayer = current.date
        isAdhanPlaying = adhan.play(url: url)
    }

    func testAdhan() {
        guard let url = settings.adhanURL else { return }
        isAdhanPlaying = adhan.play(url: url)
        adhanStatus = isAdhanPlaying ? nil : String(localized: "Couldn't play that file.")
    }

    func stopAdhan() {
        adhan.stop()
        isAdhanPlaying = false
    }

    func chooseAdhanFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose an adhan audio file")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            settings.adhanFileName = try AdhanPlayer.importFile(from: url)
            settings.adhanEnabled = true
            adhanStatus = nil
            rescheduleNotifications()
        } catch {
            adhanStatus = String(localized: "Couldn't import that file.")
        }
    }

    // MARK: Location

    func refreshLocation() {
        locationStatus = String(localized: "Locating…")
        location.requestLocation()
    }

    func setManualCity(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        locationStatus = String(localized: "Searching…")
        do {
            let (loc, name) = try await location.search(city: query)
            settings.latitude = loc.coordinate.latitude
            settings.longitude = loc.coordinate.longitude
            settings.cityName = name
            locationStatus = nil
            recalculate()
        } catch {
            locationStatus = String(localized: "Couldn't find “\(query)”.")
        }
    }

    private func locationUpdated(_ loc: CLLocation) {
        guard settings.locationMode == .automatic else { return }
        settings.latitude = loc.coordinate.latitude
        settings.longitude = loc.coordinate.longitude
        locationStatus = nil
        recalculate()
        Task {
            if let name = await location.cityName(for: loc) {
                settings.cityName = name
            }
        }
    }
}
