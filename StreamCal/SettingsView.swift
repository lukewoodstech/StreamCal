import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var shows: [Show]
    @Query private var episodes: [Episode]

    @State private var showingDeleteAllConfirm = false

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

}

#Preview {
    SettingsView()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
