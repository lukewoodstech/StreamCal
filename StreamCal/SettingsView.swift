import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var shows: [Show]
    @Query private var episodes: [Episode]

    @State private var showingDeleteAllConfirm = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

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

                Section("Notifications") {
                    switch notificationStatus {
                    case .authorized:
                        Label("Enabled", systemImage: "bell.fill")
                            .foregroundStyle(.green)
                    case .denied:
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Disabled", systemImage: "bell.slash")
                                .foregroundStyle(.orange)
                            Text("Enable notifications in iOS Settings to get episode reminders.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.caption)
                        }
                    case .notDetermined:
                        Button("Enable Episode Notifications") {
                            Task {
                                await NotificationService.shared.requestPermission()
                                notificationStatus = await NotificationService.shared.authorizationStatus()
                            }
                        }
                    default:
                        Label("Unknown", systemImage: "bell")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Data") {
                    Button("Delete All Data", role: .destructive) {
                        showingDeleteAllConfirm = true
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                notificationStatus = await NotificationService.shared.authorizationStatus()
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

    private func deleteAllData() {
        for episode in episodes { modelContext.delete(episode) }
        for show in shows { modelContext.delete(show) }
    }

}

#Preview {
    SettingsView()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
