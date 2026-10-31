import SwiftUI

@main struct MyApp: App {
    @State private var store = PrayerStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let store: PrayerStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: store.menuBarIcon)
            Text(store.menuBarTitle)
                .monospacedDigit()
        }
    }
}
