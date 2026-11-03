# Must Salah

A lightweight macOS menu bar app that keeps the five daily prayers (plus Imsak and Syuruk) in view, with a live countdown to the next prayer.

```
☀️ Dzuhur 1h 05m          ← idle: next prayer + time left
☀️ 🟠 Dzuhur 09:42        ← last 10 minutes: live seconds countdown
☀️ 🟢 Dzuhur · 12m ago    ← first 30 minutes after the prayer starts ("now" in the first minute)
```

## Features

- **Menu bar countdown:** shows the next prayer, with an icon that follows the sun through the day: horizon, sunrise, sun, sunset, moon.
- **Live final 10 minutes:** the countdown ticks every second (🟠).
- **Active prayer indicator:** 🟢 for 30 minutes after a prayer starts.
- **Dropdown panel:**
  - All 7 times (Imsak, Subuh, Syuruk, Dzuhur, Ashar, Maghrib, Isya) as columns.
  - Gregorian and Hijri date, and your city.
  - After Isya, it shows tomorrow's times.
  - On Fridays, Dzuhur becomes Jumat.
- **Alerts:**
  - A notification 10 minutes before each prayer and one at the time, switchable per prayer. Imsak alerts are optional.
  - Optional adhan, using any audio file you choose. Click the menu bar icon to stop it.
- **Location:** detected automatically, or set by searching for a city. Times are calculated on your Mac, so it works offline.
- **Per-prayer adjustments:** ±15 minutes, e.g. to match your local mosque.
- **Languages:** English, Bahasa Indonesia and العربية (with a right-to-left layout). It follows the system language or an in-app choice.
- **Launch at login.**

## Requirements

- macOS 14 Sonoma or later.
- Xcode 27 or later to build. The project uses Xcode 27's `.xcproj` project format.

## Getting started

1. Clone the repo and open `must-salah-mac.xcodeproj`.
2. Xcode resolves the one dependency, [adhan-swift](https://github.com/batoulapps/adhan-swift), automatically through Swift Package Manager.
3. In **Signing & Capabilities**, select your own development team.
4. Press **⌘R**. The app appears in the menu bar; there's no Dock icon.
5. Allow **Location** and **Notifications** when macOS asks. Until a location is found, times are calculated for Jakarta.

## How prayer times are calculated

Times use the **Kemenag RI** (Indonesian Ministry of Religious Affairs) method:

| Setting | Value |
|---|---|
| Subuh | Sun 20° below the horizon |
| Isya | Sun 18° below the horizon |
| Asr | Shafi'i (shadow length 1×) |
| Safety margin (ihtiyat) | +2 min (Dzuhur +3, Syuruk −3) |
| Rounding | Up to the next minute (Syuruk down) |
| Imsak | Subuh − 10 min |

These settings were checked against official Kemenag tables: 12 of 14 sampled times matched exactly, and the rest were within 1 minute.

Click the **ⓘ** next to "Today" in the panel to open the [official Kemenag schedule](https://bimasislam.kemenag.go.id/jadwalshalat) and compare. If your local mosque differs, use **Settings → Prayers → Adjust**.

## Privacy

- Prayer times are calculated entirely on your Mac.
- Your location is used only for that calculation and to look up the city name (via Apple's geocoder), and it's only stored on your Mac.
- There are no accounts, analytics or tracking.

## Development

```
must-salah-mac/
├── MyApp.swift            # App entry, MenuBarExtra + menu bar label
├── PrayerStore.swift      # App state: clock, menu bar state, alerts, location, language
├── Prayer.swift           # Prayer model, Kemenag calculation, menu bar states, formatting
├── Services.swift         # Location, notifications, adhan playback
├── AppSettings.swift      # User preferences (UserDefaults)
├── ContentView.swift      # Dropdown panel
├── SettingsView.swift     # In-panel settings
├── Localizable.xcstrings  # UI translations (en / id / ar)
├── InfoPlist.xcstrings    # Permission prompt translations
└── AppIcon.icon           # Icon Composer app icon
```

- **Time simulator (Debug builds only):** Settings → *Time simulator* fakes the app's clock. Use it to test the 10-minute countdown, the active state, notifications and the adhan without waiting for a real prayer time. It isn't compiled into Release builds.
- **Translations:** add new user-facing text through SwiftUI string literals or `String(localized:)`, and add its Indonesian and Arabic translations in `Localizable.xcstrings`.
- **Project settings:** there is no Info.plist or entitlements file. Info.plist keys and sandbox capabilities are build settings in `project.xcproj`.

## Credits

- Prayer time calculation: [adhan-swift](https://github.com/batoulapps/adhan-swift) by Batoul Apps (MIT).
