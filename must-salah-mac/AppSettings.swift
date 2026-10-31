import CoreLocation
import Foundation
import Observation

enum LocationMode: String {
    case automatic, manual
}

/// App UI language. Raw values are the .lproj codes in the string catalog.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, id, ar
    var id: String { rawValue }
}

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    private enum Key {
        static let locationMode = "locationMode"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let cityName = "cityName"
        static let notifyPrayers = "notifyPrayers"
        static let adhanEnabled = "adhanEnabled"
        static let adhanFileName = "adhanFileName"
        static let offsets = "offsets"
        static let language = "language"
    }

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Key.language) }
    }

    /// Per-prayer minute adjustments (e.g. to match a local mosque). Imsak follows Subuh.
    var offsets: [PrayerName: Int] {
        didSet {
            let raw = Dictionary(uniqueKeysWithValues: offsets.map { ($0.key.rawValue, $0.value) })
            UserDefaults.standard.set(raw, forKey: Key.offsets)
        }
    }

    var locationMode: LocationMode {
        didSet { UserDefaults.standard.set(locationMode.rawValue, forKey: Key.locationMode) }
    }
    var latitude: Double {
        didSet { UserDefaults.standard.set(latitude, forKey: Key.latitude) }
    }
    var longitude: Double {
        didSet { UserDefaults.standard.set(longitude, forKey: Key.longitude) }
    }
    var cityName: String {
        didSet { UserDefaults.standard.set(cityName, forKey: Key.cityName) }
    }
    /// Prayers that get a 10-min reminder, an at-time notification and adhan.
    var notifyPrayers: Set<PrayerName> {
        didSet { UserDefaults.standard.set(notifyPrayers.map(\.rawValue), forKey: Key.notifyPrayers) }
    }
    var adhanEnabled: Bool {
        didSet { UserDefaults.standard.set(adhanEnabled, forKey: Key.adhanEnabled) }
    }
    /// File name inside `AdhanPlayer.directory`.
    var adhanFileName: String? {
        didSet { UserDefaults.standard.set(adhanFileName, forKey: Key.adhanFileName) }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var adhanURL: URL? {
        guard let adhanFileName else { return nil }
        let url = AdhanPlayer.directory.appendingPathComponent(adhanFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    init() {
        let d = UserDefaults.standard
        locationMode = LocationMode(rawValue: d.string(forKey: Key.locationMode) ?? "") ?? .automatic
        // Default: Jakarta, until a real location is known.
        latitude = d.object(forKey: Key.latitude) as? Double ?? -6.2088
        longitude = d.object(forKey: Key.longitude) as? Double ?? 106.8456
        cityName = d.string(forKey: Key.cityName) ?? "Jakarta"
        if let saved = d.stringArray(forKey: Key.notifyPrayers) {
            notifyPrayers = Set(saved.compactMap(PrayerName.init(rawValue:)))
        } else {
            notifyPrayers = Set(PrayerName.prayers)
        }
        adhanEnabled = d.object(forKey: Key.adhanEnabled) as? Bool ?? false
        adhanFileName = d.string(forKey: Key.adhanFileName)
        language = AppLanguage(rawValue: d.string(forKey: Key.language) ?? "") ?? .system
        let rawOffsets = d.dictionary(forKey: Key.offsets) as? [String: Int] ?? [:]
        offsets = Dictionary(uniqueKeysWithValues: rawOffsets.compactMap { key, value in
            PrayerName(rawValue: key).map { ($0, value) }
        })
    }
}
