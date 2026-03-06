import SwiftUI
import SwiftData

@main
struct StreamCalApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Request notification permission on first launch (no-op if already decided)
                    await NotificationService.shared.requestPermission()
                }
        }
        .modelContainer(for: [Show.self, Episode.self]) { result in
            guard let container = try? result.get() else { return }
            // Background refresh episodes + reschedule notifications on every launch
            Task { @MainActor in
                await RefreshService.shared.refreshAllShows(modelContext: container.mainContext)
            }
        }
    }
}
