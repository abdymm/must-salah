import Adhan
import CoreLocation
import Foundation

enum PrayerName: String, CaseIterable, Codable, Identifiable {
    case imsak, subuh, syuruk, dzuhur, ashar, maghrib, isya

    var id: String { rawValue }

    /// The five obligatory prayers. Imsak and Syuruk are informational only.
    static let prayers: [PrayerName] = [.subuh, .dzuhur, .ashar, .maghrib, .isya]

    /// Times that can have alerts. Imsak is alert-only (no adhan, no menu bar countdown).
    static let alertable: [PrayerName] = [.imsak] + prayers

    var isPrayer: Bool { Self.prayers.contains(self) }

    /// SF Symbol following the sun's position through the day.
    var icon: String {
        switch self {
        case .imsak: "moon.stars.fill"
        case .subuh: "sun.horizon.fill"
        case .syuruk: "sunrise.fill"
        case .dzuhur: "sun.max.fill"
        case .ashar: "sun.min.fill"
        case .maghrib: "sunset.fill"
        case .isya: "moon.fill"
        }
    }

    var title: String {
        switch self {
        case .imsak: String(localized: "Imsak")
        case .subuh: String(localized: "Subuh")
        case .syuruk: String(localized: "Syuruk")
        case .dzuhur: String(localized: "Dzuhur")
        case .ashar: String(localized: "Ashar")
        case .maghrib: String(localized: "Maghrib")
        case .isya: String(localized: "Isya")
        }
    }
}

struct PrayerTime: Identifiable, Hashable {
    let name: PrayerName
    let date: Date

    var id: Date { date }

    /// Dzuhur becomes Jumat on Fridays.
    var title: String {
        if name == .dzuhur, Calendar.current.component(.weekday, from: date) == 6 {
            return String(localized: "Jumat")
        }
        return name.title
    }
}

enum PrayerCalculator {
    static let methodName = "Kemenag RI"
    /// Official Kemenag prayer schedule, linked from the panel's info icon.
    static let sourceURL = URL(string: "https://bimasislam.kemenag.go.id/jadwalshalat")!

    /// Imsak = Subuh − 10 minutes (Indonesian convention).
    static let imsakOffset: TimeInterval = -10 * 60

    /// Kemenag RI: Subuh 20°, Isya 18°, Shafi'i Asr, +2 min ihtiyat (Dzuhur +3), rounded UP to the minute.
    /// Syuruk is rounded down by Kemenag; with round-up that's −4 here (≈ floor(x − 3)).
    /// Checked against official Kemenag tables (Jakarta 3 Mar 2025, Blitar 17 Apr 2026): 12/14 exact, rest ±1 min.
    /// `userOffsets` are the per-prayer minute tweaks from Settings, added on top.
    static func kemenag(userOffsets: [PrayerName: Int] = [:]) -> CalculationParameters {
        func offset(_ name: PrayerName) -> Int { userOffsets[name] ?? 0 }
        var params = CalculationMethod.other.params
        params.fajrAngle = 20
        params.ishaAngle = 18
        params.madhab = .shafi
        params.rounding = .up
        params.adjustments = PrayerAdjustments(
            fajr: 2 + offset(.subuh),
            sunrise: -4,
            dhuhr: 3 + offset(.dzuhur),
            asr: 2 + offset(.ashar),
            maghrib: 2 + offset(.maghrib),
            isha: 2 + offset(.isya)
        )
        return params
    }

    static func times(for day: Date, coordinate: CLLocationCoordinate2D, offsets: [PrayerName: Int] = [:]) -> [PrayerTime] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let coordinates = Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)

        guard let p = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: kemenag(userOffsets: offsets)) else {
            return []
        }
        return [
            PrayerTime(name: .imsak, date: p.fajr.addingTimeInterval(imsakOffset)),
            PrayerTime(name: .subuh, date: p.fajr),
            PrayerTime(name: .syuruk, date: p.sunrise),
            PrayerTime(name: .dzuhur, date: p.dhuhr),
            PrayerTime(name: .ashar, date: p.asr),
            PrayerTime(name: .maghrib, date: p.maghrib),
            PrayerTime(name: .isya, date: p.isha),
        ]
    }
}

/// What the menu bar should show right now.
enum MenuBarState: Equatable {
    /// More than 10 minutes before the next prayer.
    case idle(next: PrayerTime)
    /// 10 minutes or less before the next prayer — live seconds countdown.
    case approaching(next: PrayerTime)
    /// Within 30 minutes after a prayer started.
    case active(current: PrayerTime)

    static let approachWindow: TimeInterval = 10 * 60
    static let activeWindow: TimeInterval = 30 * 60

    /// `prayers` must contain only the five prayers, sorted, spanning today and tomorrow.
    static func compute(now: Date, prayers: [PrayerTime]) -> MenuBarState? {
        let next = prayers.first { $0.date > now }
        let current = prayers.last { $0.date <= now }

        if let next, next.date.timeIntervalSince(now) <= approachWindow {
            return .approaching(next: next)
        }
        if let current, now.timeIntervalSince(current.date) < activeWindow {
            return .active(current: current)
        }
        if let next {
            return .idle(next: next)
        }
        return nil
    }

    var next: PrayerTime? {
        switch self {
        case .idle(let next), .approaching(let next): next
        case .active: nil
        }
    }

    var active: PrayerTime? {
        if case .active(let current) = self { return current }
        return nil
    }
}

enum Fmt {
    /// The language the app is actually running in (en / id / ar), for month and day names.
    private static let appLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

    /// Times and countdowns always use Latin digits so "09:42" and "1h 23m" never mix digit styles.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let gregorianFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = appLocale
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM yyyy")
        return f
    }()

    private static let hijriFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .islamicUmmAlQura)
        f.locale = appLocale
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func gregorian(_ date: Date) -> String { gregorianFormatter.string(from: date) }
    /// "10 Jumada I 1448 H" (suffix is localized: H / H / هـ).
    static func hijri(_ date: Date) -> String {
        let day = hijriFormatter.string(from: date)
        return String(localized: "\(day) H")
    }

    /// "1h 23m" / "23m". Countdowns round up, so it never reads "10m" while still idle;
    /// elapsed time rounds down, so "12m ago" doesn't jump ahead when a tick fires a moment late.
    static func hoursMinutes(_ interval: TimeInterval, rounding: FloatingPointRoundingRule = .up) -> String {
        let minutes = max(0, Int((interval / 60).rounded(rounding)))
        let h = String(minutes / 60), m = String(minutes % 60)
        if minutes >= 60 {
            let mm = String(format: "%02d", minutes % 60)
            return String(localized: "\(h)h \(mm)m")
        }
        return String(localized: "\(m)m")
    }

    /// "09:42"
    static func minutesSeconds(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
