import SwiftUI
import SwiftData
import RevenueCat

@main
struct StreamCalApp: App {

    @StateObject private var purchaseService = PurchaseService.shared

    init() {
        UserDefaults.standard.register(defaults: [
            "airReminderHour": 9,
            "weeklySummaryEnabled": true,
            "weeklySummaryHour": 20,
            "gameReminderMinutesBefore": 120,
            "advanceReminderEnabled": false
        ])

        PurchaseService.shared.configure(apiKey: "test_pIbHuoHBOBRUopPdTwPgbMGyCOz")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseService)
                .task {
                    await NotificationService.shared.requestPermission()
                }
        }
        .modelContainer(for: [Show.self, Episode.self, Movie.self, SportTeam.self, SportGame.self, AnimeShow.self, AnimeEpisode.self]) { result in
            guard let container = try? result.get() else { return }
            Task { @MainActor in
                await RefreshService.shared.refreshAll(modelContext: container.mainContext)
                await TraktService.shared.syncHistory(modelContext: container.mainContext)
            }
        }
    }
}
