import SwiftUI
import SwiftData

struct ContentView: View {

    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "rectangle.stack.fill")
                }

            NextUpView()
                .tabItem {
                    Label("Next Up", systemImage: "play.circle.fill")
                }

            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
