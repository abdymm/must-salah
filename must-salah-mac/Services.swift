import AVFoundation
import CoreLocation
import Foundation
import UserNotifications

// MARK: - Location

final class LocationService: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((CLLocation) -> Void)?
    var onError: ((String) -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var wantsLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        wantsLocation = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            wantsLocation = false
            onError?(String(localized: "Location access is off. Turn it on in System Settings → Privacy & Security → Location Services, or set a city manually."))
        default:
            manager.requestLocation()
        }
    }

    func cityName(for location: CLLocation) async -> String? {
        let placemark = try? await geocoder.reverseGeocodeLocation(location).first
        return placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.administrativeArea
    }

    func search(city: String) async throws -> (CLLocation, String) {
        let placemarks = try await geocoder.geocodeAddressString(city)
        guard let placemark = placemarks.first, let location = placemark.location else {
            throw CLError(.geocodeFoundNoResult)
        }
        return (location, placemark.locality ?? placemark.name ?? city)
    }

    private func authorizationChanged() {
        guard wantsLocation, manager.authorizationStatus != .notDetermined else { return }
        requestLocation()
    }

    private func received(_ location: CLLocation) {
        wantsLocation = false
        onUpdate?(location)
    }

    private func failed() {
        wantsLocation = false
        onError?(String(localized: "Couldn't get your location. Using the last known one."))
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.received(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.failed() }
    }
}

// MARK: - Notifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var timeOffset: TimeInterval = 0

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// True when the user turned notifications off for this app in System Settings.
    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// Replaces all pending notifications with a 10-min reminder and an at-time alert per enabled prayer.
    /// `now`/`timeOffset` come from the store's (possibly simulated) clock; triggers are shifted
    /// back to real time so they fire when the simulated clock reaches each prayer.
    func reschedule(prayers: [PrayerTime], enabled: Set<PrayerName>, adhanWillPlay: Bool, now: Date, timeOffset: TimeInterval) {
        center.removeAllPendingNotificationRequests()
        self.timeOffset = timeOffset

        for prayer in prayers where enabled.contains(prayer.name) && PrayerName.alertable.contains(prayer.name) {
            let time = Fmt.time(prayer.date)
            let adhanPlays = adhanWillPlay && prayer.name.isPrayer
            add(id: "before-\(prayer.date.timeIntervalSince1970)",
                at: prayer.date.addingTimeInterval(-MenuBarState.approachWindow),
                title: String(localized: "\(prayer.title) in 10 minutes"),
                body: String(localized: "\(prayer.title) is at \(time)."),
                sound: .default,
                now: now)
            add(id: "at-\(prayer.date.timeIntervalSince1970)",
                at: prayer.date,
                title: prayer.name == .imsak
                    ? String(localized: "It's Imsak")
                    : String(localized: "It's time for \(prayer.title)"),
                body: prayer.name == .imsak
                    ? String(localized: "Imsak · \(time) — Subuh in 10 minutes.")
                    : "\(prayer.title) · \(time)",
                // The adhan itself is the sound when it's enabled.
                sound: adhanPlays ? nil : .default,
                now: now)
        }
    }

    private func add(id: String, at date: Date, title: String, body: String, sound: UNNotificationSound?, now: Date) {
        guard date > now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        let realDate = date.addingTimeInterval(-timeOffset)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: realDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { _ in }
    }

    /// Show banners even though the app is always "running".
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

// MARK: - Adhan audio

final class AdhanPlayer: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    private var player: AVAudioPlayer?

    /// Where the user's chosen adhan file is copied (inside the app's sandbox container).
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Adhan", isDirectory: true)
    }

    /// Copies a user-picked audio file into the app container so it stays readable after relaunch.
    static func importFile(from source: URL) throws -> String {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        try? fm.removeItem(at: directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: directory.appendingPathComponent(source.lastPathComponent))
        return source.lastPathComponent
    }

    @discardableResult
    func play(url: URL) -> Bool {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        player.delegate = self
        self.player = player
        return player.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func finished() {
        player = nil
        onFinish?()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finished() }
    }
}
