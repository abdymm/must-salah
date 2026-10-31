import AppKit
import SwiftUI

/// The dropdown panel shown when clicking the menu bar item.
struct ContentView: View {
    @Environment(PrayerStore.self) private var store

    var body: some View {
        Group {
            if store.showingSettings {
                SettingsView()
            } else {
                mainPanel
            }
        }
        .padding(14)
        .frame(width: 420)
        // Clicking the menu bar icon stops a playing adhan.
        .onAppear {
            store.stopAdhan()
            Task { await store.refreshNotificationStatus() }
        }
        .onDisappear { store.showingSettings = false }
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if store.isAdhanPlaying {
                Button {
                    store.stopAdhan()
                } label: {
                    Label("Stop Adhan", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

            if store.isSimulating {
                HStack(spacing: 8) {
                    Image(systemName: "flask.fill").foregroundStyle(.purple)
                    Text("Simulated time · \(Fmt.time(store.now))")
                        .font(.caption)
                        .monospacedDigit()
                    Spacer(minLength: 4)
                    Button("Reset") { store.resetSimulation() }
                        .controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.12)))
            }

            if store.notificationsDenied {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
                    Text("Notifications are off, so you won't get prayer alerts.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Turn On") { store.openNotificationSettings() }
                        .controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }

            Divider()

            let displayed = store.displayedTimes
            HStack(spacing: 4) {
                Text(displayed.label.uppercased())
                    .font(.caption2.weight(.semibold))
                Link(destination: PrayerCalculator.sourceURL) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                }
                .help("Calculated on your Mac using the \(PrayerCalculator.methodName) method (Subuh 20°, Isya 18°). Click to compare with the official Kemenag schedule.")
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(displayed.times) { PrayerColumn(prayer: $0) }
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Spacer(minLength: 8)
                Label(store.settings.cityName, systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let subheadline {
                Text(subheadline)
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Label {
                Text(verbatim: "\(Fmt.gregorian(store.now)) · \(Fmt.hijri(store.now))")
            } icon: {
                Image(systemName: "calendar")
            }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private var headline: String {
        switch store.state {
        case .idle(let next):
            let remaining = Fmt.hoursMinutes(next.date.timeIntervalSince(store.now))
            return String(localized: "\(next.title) in \(remaining)")
        case .approaching(let next):
            let remaining = Fmt.minutesSeconds(next.date.timeIntervalSince(store.now))
            return String(localized: "\(next.title) in \(remaining)")
        case .active(let current):
            return String(localized: "It's \(current.title) time")
        case nil:
            return "Must Salah"
        }
    }

    private var subheadline: String? {
        switch store.state {
        case .idle(let next), .approaching(let next):
            let time = Fmt.time(next.date)
            return String(localized: "at \(time)")
        case .active(let current):
            let elapsed = Fmt.hoursMinutes(store.now.timeIntervalSince(current.date))
            return String(localized: "Started \(elapsed) ago")
        case nil:
            return nil
        }
    }

    private var footer: some View {
        HStack {
            Text(PrayerCalculator.methodName).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                store.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }
}

private struct PrayerColumn: View {
    @Environment(PrayerStore.self) private var store
    let prayer: PrayerTime

    private var isActive: Bool { store.state?.active == prayer }
    private var isNext: Bool { store.state?.next == prayer }
    private var isPast: Bool { prayer.date <= store.now && !isActive }
    private var isHighlighted: Bool { isActive || isNext }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: prayer.name.icon)
                .font(.system(size: 16))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.green : isNext ? Color.accentColor : Color.secondary)
                .frame(height: 20)
            Text(prayer.title)
                .font(.system(size: 11, weight: isHighlighted ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(Fmt.time(prayer.date))
                .font(.system(size: 13, weight: isHighlighted ? .semibold : .medium))
                .monospacedDigit()
        }
        .foregroundStyle(isPast ? Color.secondary : Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.green.opacity(0.15) : isNext ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }
}
