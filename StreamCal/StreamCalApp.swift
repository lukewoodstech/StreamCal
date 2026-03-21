import SwiftUI
import SwiftData

@main
struct StreamCalApp: App {

    init() {
        UserDefaults.standard.register(defaults: [
            "airReminderHour": 9,   // 9:00 AM — new episode air-date reminder
            "planReminderHour": 20  // 8:00 PM — tonight's plan reminder
        ])
    }

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
