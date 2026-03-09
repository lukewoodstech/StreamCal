import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var shows: [Show]
    @Query private var episodes: [Episode]

    @State private var showingDeleteAllConfirm = false
    @State private var showingDeletedBanner = false
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
                    // Attach confirmationDialog directly to the button so the
                    // action sheet anchors to the right place on screen.
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
                        Text("This will permanently delete all \(shows.count) shows and \(episodes.count) episodes. This cannot be undone.")
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                notificationStatus = await NotificationService.shared.authorizationStatus()
            }
            // Success banner overlaid at the top
            .overlay(alignment: .top) {
                if showingDeletedBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("All data deleted")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: showingDeletedBanner)
        }
    }

    private func deleteAllData() {
        do {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

            // Delete Shows only — Episodes are cascade-deleted automatically
            // via the @Relationship(deleteRule: .cascade) on Show.episodes.
            // Trying to batch-delete Episodes first triggers a SwiftData OTO
            // constraint violation on the Episode.show inverse relationship.
            try modelContext.delete(model: Show.self)
            try modelContext.save()

            showingDeletedBanner = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                showingDeletedBanner = false
            }
        } catch {
            print("Delete all data failed: \(error)")
        }
    }

}

#Preview {
    SettingsView()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
