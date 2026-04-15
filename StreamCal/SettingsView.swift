import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var shows: [Show]
    @Query private var episodes: [Episode]
    @Query private var movies: [Movie]
    @Query private var animeShows: [AnimeShow]
    @Query private var teams: [SportTeam]

    @EnvironmentObject private var purchaseService: PurchaseService

    @State private var showingDeleteAllConfirm = false
    @State private var showingDeletedBanner = false
    @State private var showingNotifications = false
    @State private var showingPlatforms = false
    @State private var showingPaywall = false
    @State private var showingProManagement = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 10) {
                                BrandMark(size: 44, showBackground: true)
                                Text("StreamCal")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Text("Version \(appVersion) (\(buildNumber))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                    }

                    Section("About") {
                        LabeledContent("Shows", value: "\(shows.count)")
                        LabeledContent("Movies", value: "\(movies.count)")
                        LabeledContent("Anime", value: "\(animeShows.count)")
                        LabeledContent("Sports Teams", value: "\(teams.count)")
                        LabeledContent("Episodes", value: "\(episodes.count)")
                        Link(destination: URL(string: "https://lukewoodstech.github.io/streamcal-privacy")!) {
                            HStack {
                                Text("Privacy Policy")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .imageScale(.small)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Link(destination: URL(string: "mailto:luke@lukewoodstech.com")!) {
                            HStack {
                                Text("Contact / Support")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .imageScale(.small)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Section("Personalize") {
                        Button { showingNotifications = true } label: {
                            HStack {
                                Label("Notifications", systemImage: "bell")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .imageScale(.small)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Button { showingPlatforms = true } label: {
                            HStack {
                                Label("Streaming Services", systemImage: "play.tv")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .imageScale(.small)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Section("Connected Accounts") {
                        TraktConnectionRow()
                    }

                    Section("Smart Features") {
                        if purchaseService.isPro {
                            Button {
                                showingProManagement = true
                            } label: {
                                HStack {
                                    Label("StreamCal Pro", systemImage: "sparkles")
                                        .foregroundStyle(DS.Color.ai)
                                    Spacer()
                                    Text("Active")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .imageScale(.small)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.primary)
                        } else {
                            Button {
                                showingPaywall = true
                            } label: {
                                HStack {
                                    Label("Upgrade to Pro", systemImage: "sparkles")
                                        .foregroundStyle(Color.accentColor)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .imageScale(.small)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }

                    Section("Data") {
                        Button("Delete All Data", role: .destructive) {
                            showingDeleteAllConfirm = true
                        }
                    }
                }
                .disabled(showingDeleteAllConfirm)

                if showingDeleteAllConfirm {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    VStack(spacing: 16) {
                        Text("Delete All Data?")
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)

                        Text("This will permanently delete all shows, movies, anime, and sports data. This cannot be undone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        VStack(spacing: 8) {
                            Button(role: .destructive) {
                                showingDeleteAllConfirm = false
                                deleteAllData()
                            } label: {
                                Text("Delete All Data")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)

                            Button("Cancel") {
                                showingDeleteAllConfirm = false
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .heavyShadow()
                    .padding(.horizontal, 32)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingNotifications) {
                NotificationSettingsSheet()
            }
            .sheet(isPresented: $showingPlatforms) {
                StreamingServicesSheet()
            }
            .sheet(isPresented: $showingPaywall) {
                AppPaywallView().environmentObject(purchaseService)
            }
            .sheet(isPresented: $showingProManagement) {
                ProManagementSheet().environmentObject(purchaseService)
            }
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
                    .lightShadow()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: showingDeletedBanner)
            .animation(.spring(duration: 0.3), value: showingDeleteAllConfirm)
        }
    }

    private func deleteAllData() {
        do {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            try modelContext.delete(model: Show.self)
            try modelContext.delete(model: Movie.self)
            try modelContext.delete(model: AnimeShow.self)
            try modelContext.delete(model: SportTeam.self)
            try modelContext.delete(model: SportGame.self)
            try modelContext.save()

            showingDeletedBanner = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                showingDeletedBanner = false
            }
        } catch {
            // non-fatal
        }
    }
}

// MARK: - Streaming Services Sheet

struct StreamingServicesSheet: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("preferredPlatforms") private var preferredPlatformsRaw: String = ""

    private var preferredPlatforms: Set<String> {
        Set(preferredPlatformsRaw.split(separator: ",").map(String.init))
    }

    private var platformsForPicker: [StreamingPlatform] {
        StreamingPlatform.allCases.filter { $0 != .other }
    }

    private func togglePlatform(_ platform: String) {
        var platforms = preferredPlatforms
        if platforms.contains(platform) { platforms.remove(platform) } else { platforms.insert(platform) }
        preferredPlatformsRaw = platforms.sorted().joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(platformsForPicker) { platform in
                        let selected = preferredPlatforms.contains(platform.rawValue)
                        Button {
                            togglePlatform(platform.rawValue)
                        } label: {
                            HStack(spacing: 6) {
                                Text(platform.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .foregroundStyle(selected ? .white : platform.badgeColor)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(selected ? platform.badgeColor : platform.badgeColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Text("Shows and movies not available on your services are flagged in the library.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
            .navigationTitle("Streaming Services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Trakt Connection Row

struct TraktConnectionRow: View {
    @StateObject private var trakt = TraktService.shared
    @Environment(\.modelContext) private var modelContext

    @State private var showingDisconnectConfirm = false

    var body: some View {
        Group {
            if trakt.isConnected {
                HStack {
                    Label("Trakt", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .foregroundStyle(.primary)
                    Spacer()
                    if trakt.isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if trakt.lastSyncedCount > 0 {
                        Text("\(trakt.lastSyncedCount) synced")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Connected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Disconnect Trakt", role: .destructive) {
                    showingDisconnectConfirm = true
                }
                .confirmationDialog("Disconnect Trakt?", isPresented: $showingDisconnectConfirm, titleVisibility: .visible) {
                    Button("Disconnect", role: .destructive) { trakt.disconnect() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Watch history synced from Trakt will remain, but future syncs will stop.")
                }
            } else {
                Button {
                    trakt.connect()
                } label: {
                    HStack {
                        Label("Connect Trakt", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        // Trigger an immediate sync the moment the user successfully connects
        .onChange(of: trakt.isConnected) { _, connected in
            guard connected else { return }
            Task { await trakt.syncHistory(modelContext: modelContext) }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
