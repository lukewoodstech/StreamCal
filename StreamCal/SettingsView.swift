import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var shows: [Show]
    @Query private var episodes: [Episode]

    @State private var showingDeleteAllConfirm = false
    @State private var showingAddSampleConfirm = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    LabeledContent("Version", value: "\(appVersion) (\(buildNumber))")
                    LabeledContent("Shows", value: "\(shows.count)")
                    LabeledContent("Episodes", value: "\(episodes.count)")
                }

                Section("Data") {
                    Button("Load Sample Data") {
                        showingAddSampleConfirm = true
                    }
                    .confirmationDialog(
                        "Load Sample Data?",
                        isPresented: $showingAddSampleConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Load Sample Data") { loadSampleData() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will add a few sample shows and episodes.")
                    }

                    Button("Delete All Data", role: .destructive) {
                        showingDeleteAllConfirm = true
                    }
                    .confirmationDialog(
                        "Delete All Data?",
                        isPresented: $showingDeleteAllConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete All Data", role: .destructive) { deleteAllData() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete all shows and episodes. This cannot be undone.")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func deleteAllData() {
        for episode in episodes { modelContext.delete(episode) }
        for show in shows { modelContext.delete(show) }
    }

    private func loadSampleData() {
        let cal = Calendar.current
        let sampleShows: [(String, String, [(Int, Int, String, Int)])] = [
            ("Severance", "Apple TV+", [
                (2, 1, "Goodbye, Mrs. Selvig", -14),
                (2, 2, "Famine, Flood, and Fire", -7),
                (2, 3, "Woe's Hollow", 0),
                (2, 4, "Cooked", 7),
                (2, 5, "Attainder", 14)
            ]),
            ("The Bear", "Hulu", [
                (3, 1, "Tomorrow", 3),
                (3, 2, "Next", 10),
                (3, 3, "After", 17)
            ]),
            ("Andor", "Disney+", [
                (2, 1, "Chapter 11", 5),
                (2, 2, "Chapter 12", 12),
                (2, 3, "Chapter 13", 19)
            ])
        ]

        for (title, platform, epData) in sampleShows {
            let show = Show(title: title, platform: platform)
            modelContext.insert(show)
            for (season, epNum, epTitle, dayOffset) in epData {
                let airDate = cal.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
                let ep = Episode(
                    seasonNumber: season,
                    episodeNumber: epNum,
                    title: epTitle,
                    airDate: airDate,
                    isWatched: dayOffset < 0
                )
                ep.show = show
                modelContext.insert(ep)
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
