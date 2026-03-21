import SwiftUI
import SwiftData

struct ShowDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let show: Show

    @State private var showingEditShow = false
    @State private var isRefreshing = false
    @State private var refreshError: String? = nil

    var body: some View {
        List {
            posterSection
            showInfoSection
            if let overview = show.overview, !overview.isEmpty {
                overviewSection(overview)
            }
            episodesSection
        }
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Show") { showingEditShow = true }
                    if show.tmdbID != nil {
                        Button {
                            Task { await refreshEpisodes() }
                        } label: {
                            Label("Refresh Episodes", systemImage: "arrow.clockwise")
                        }
                    }
                    let airedUnwatched = show.episodes.filter {
                        !$0.isWatched &&
                        $0.airDate != .distantFuture &&
                        $0.airDate <= Calendar.current.startOfDay(for: .now)
                    }
                    if !airedUnwatched.isEmpty {
                        Button {
                            for ep in airedUnwatched {
                                ep.isWatched = true
                            }
                            Task {
                                await NotificationService.shared.scheduleNotifications(for: show)
                            }
                        } label: {
                            Label("Mark All Aired as Watched", systemImage: "checkmark.circle.fill")
                        }
                    }
                    Button {
                        show.notificationsEnabled.toggle()
                        if show.notificationsEnabled {
                            Task { await NotificationService.shared.scheduleNotifications(for: show) }
                        } else {
                            Task { await NotificationService.shared.cancelNotifications(for: show) }
                        }
                    } label: {
                        Label(
                            show.notificationsEnabled ? "Mute Notifications" : "Unmute Notifications",
                            systemImage: show.notificationsEnabled ? "bell.slash" : "bell"
                        )
                    }

                    Divider()
                    Button(show.isArchived ? "Unarchive" : "Archive") {
                        show.isArchived.toggle()
                        show.updatedAt = .now
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditShow) {
            AddShowSheet(existingShow: show)
        }
    }

    // MARK: - Poster

    @ViewBuilder
    private var posterSection: some View {
        if let urlString = show.posterURL, let url = URL(string: urlString) {
            Section {
                HStack {
                    Spacer()
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(radius: 4)
                        case .failure, .empty:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: 160, maxHeight: 240)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
        }
    }

    // MARK: - Info

    private var showInfoSection: some View {
        Section("Info") {
            LabeledContent("Platform") {
                PlatformBadge(platform: show.platform)
            }
            if let status = show.showStatus, !status.isEmpty {
                LabeledContent("Status", value: status)
            }
            if show.isArchived {
                Label("Archived", systemImage: "archivebox")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            if !show.notes.isEmpty {
                Text(show.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Overview

    private func overviewSection(_ overview: String) -> some View {
        Section("Overview") {
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Episodes

    private var episodesSection: some View {
        Section {
            if isRefreshing {
                HStack {
                    ProgressView()
                    Text("Refreshing episodes…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let error = refreshError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if show.sortedEpisodes.isEmpty {
                Text("No episodes yet.")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(show.sortedEpisodes) { episode in
                    EpisodeRowView(episode: episode)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(episode)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                episode.isWatched.toggle()
                                let capturedShow = show
                                Task {
                                    await NotificationService.shared.scheduleNotifications(for: capturedShow)
                                }
                            } label: {
                                Label(
                                    episode.isWatched ? "Unwatch" : "Watched",
                                    systemImage: episode.isWatched ? "eye.slash" : "checkmark"
                                )
                            }
                            .tint(episode.isWatched ? .gray : .green)
                        }
                        .contextMenu {
                            EpisodeContextMenuItems(episode: episode, show: show)
                        }
                }
            }
        } header: {
            Text("Episodes")
        }
    }

    // MARK: - Refresh

    private func refreshEpisodes() async {
        isRefreshing = true
        refreshError = nil
        do {
            try await RefreshService.shared.refreshSingleShow(show, modelContext: modelContext)
        } catch {
            refreshError = error.localizedDescription
        }
        isRefreshing = false
    }
}

// MARK: - Episode Row

struct EpisodeRowView: View {
    let episode: Episode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(episode.isWatched ? .secondary : .primary)
                Text(episode.airDate == .distantFuture ? "TBA" : episode.airDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()

            HStack(spacing: 6) {
                if episode.isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

#Preview {
    ShowDetailPreviewWrapper()
}

private struct ShowDetailPreviewWrapper: View {
    var body: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Show.self, Episode.self, configurations: config)
        let show = Show(title: "Severance", platform: "Apple TV+", notes: "Great thriller",
                        overview: "A thriller about work-life separation taken to the extreme.")
        container.mainContext.insert(show)
        let ep1 = Episode(seasonNumber: 2, episodeNumber: 1, title: "Goodbye, Mrs. Selvig",
                          airDate: Calendar.current.date(byAdding: .day, value: 3, to: .now)!)
        ep1.show = show
        container.mainContext.insert(ep1)
        return NavigationStack {
            ShowDetailView(show: show)
        }
        .modelContainer(container)
    }
}
