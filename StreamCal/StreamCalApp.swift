import SwiftUI
import SwiftData

@main
struct StreamCalApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Show.self, Episode.self])
    }
}
