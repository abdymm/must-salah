import SwiftUI

struct SettingsView: View {
    @Environment(PrayerStore.self) private var store
    @State private var cityQuery = ""

    var body: some View {
        @Bindable var settings = store.settings

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    store.showingSettings = false
                } label: {
                    Image(systemName: "chevron.backward") // flips automatically in Arabic
                }
                .buttonStyle(.borderless)
                Text("Settings").font(.headline)
            }

            section("Location") {
                Picker("Location", selection: $settings.locationMode) {
                    Text("Automatic").tag(LocationMode.automatic)
                    Text("Manual").tag(LocationMode.manual)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: settings.locationMode) {
                    if settings.locationMode == .automatic { store.refreshLocation() }
                }

                HStack {
                    Label(settings.cityName, systemImage: "location.fill")
                    Spacer()
                    if settings.locationMode == .automatic {
                        Button("Update") { store.refreshLocation() }
                    }
                }

                if settings.locationMode == .manual {
                    HStack {
                        TextField("City, e.g. Bandung", text: $cityQuery)
                            .onSubmit(searchCity)
                        Button("Set", action: searchCity)
                            .disabled(cityQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if let status = store.locationStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            section("Prayers") {
                HStack {
                    Spacer()
                    Text("Adjust").frame(width: 120, alignment: .center)
                    Text("Alert").frame(width: 36, alignment: .center)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                ForEach(PrayerName.alertable) { name in
                    HStack {
                        Text(name.title)
                        Spacer()
                        Group {
                            if name == .imsak {
                                Text("Subuh − 10 min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                HStack(spacing: 4) {
                                    Text(offsetLabel(for: name))
                                        .monospacedDigit()
                                        .foregroundStyle(store.settings.offsets[name, default: 0] == 0 ? Color.secondary : Color.primary)
                                        .frame(width: 56, alignment: .trailing)
                                    Stepper("Adjust \(name.title)", value: offsetBinding(for: name), in: -15...15)
                                        .labelsHidden()
                                }
                            }
                        }
                        .frame(width: 120, alignment: .trailing)
                        Toggle("Alert for \(name.title)", isOn: notifyBinding(for: name))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .frame(width: 36)
                    }
                }

                Text("Adjust shifts a time by whole minutes, e.g. to match your mosque. Alerts come 10 min before and at the time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Adhan") {
                Toggle("Play adhan at prayer time", isOn: $settings.adhanEnabled)
                    .onChange(of: settings.adhanEnabled) { store.rescheduleNotifications() }
                    .disabled(settings.adhanURL == nil)
                HStack {
                    Group {
                        if let fileName = settings.adhanFileName {
                            Text(verbatim: fileName)
                        } else {
                            Text("No file chosen")
                        }
                    }
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { store.chooseAdhanFile() }
                    Button {
                        store.isAdhanPlaying ? store.stopAdhan() : store.testAdhan()
                    } label: {
                        Text(store.isAdhanPlaying ? LocalizedStringKey("Stop") : LocalizedStringKey("Test"))
                    }
                    .disabled(settings.adhanURL == nil)
                }
                if let status = store.adhanStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            section("Language") {
                Picker("Language", selection: Binding(
                    get: { store.settings.language },
                    set: { store.setLanguage($0) }
                )) {
                    Text("System").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.en)
                    Text(verbatim: "Bahasa Indonesia").tag(AppLanguage.id)
                    Text(verbatim: "العربية").tag(AppLanguage.ar)
                }
                .labelsHidden()
                Text("Changing the language restarts the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            section("Time simulator (debug)") {
                DatePicker(
                    "Time",
                    selection: Binding(get: { store.now }, set: { store.simulate($0) }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.stepperField)

                HStack {
                    Button("Next prayer −10m 5s") { store.simulateBeforeNextPrayer(seconds: 605) }
                        .help("Countdown mode starts 5 seconds later")
                    Button("Next prayer −5s") { store.simulateBeforeNextPrayer(seconds: 5) }
                        .help("Prayer starts 5 seconds later: active state, notification, adhan")
                    Spacer()
                    Button("Reset") { store.resetSimulation() }
                        .disabled(!store.isSimulating)
                }

                Text("Shifts the app's clock; it keeps ticking from there. Not saved, resets on relaunch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            Toggle("Launch at login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
        }
    }

    private func searchCity() {
        let query = cityQuery
        Task { await store.setManualCity(query) }
    }

    private func offsetLabel(for name: PrayerName) -> String {
        let minutes = store.settings.offsets[name, default: 0]
        let value = String(abs(minutes))
        if minutes == 0 { return String(localized: "0 min") }
        return minutes > 0 ? String(localized: "+\(value) min") : String(localized: "−\(value) min")
    }

    private func offsetBinding(for name: PrayerName) -> Binding<Int> {
        Binding(
            get: { store.settings.offsets[name, default: 0] },
            set: { minutes in
                store.settings.offsets[name] = minutes == 0 ? nil : minutes
                store.recalculate()
            }
        )
    }

    private func notifyBinding(for name: PrayerName) -> Binding<Bool> {
        Binding(
            get: { store.settings.notifyPrayers.contains(name) },
            set: { isOn in
                if isOn {
                    store.settings.notifyPrayers.insert(name)
                } else {
                    store.settings.notifyPrayers.remove(name)
                }
                store.rescheduleNotifications()
            }
        )
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
