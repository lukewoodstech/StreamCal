import SwiftUI
import SwiftData

struct ShowDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let show: Show

    @State private var showingEditShow = false
    @State private var isRefreshing = false
    @State private var refreshError: String? = nil

    private var watchPlatforms: [StreamingPlatform] { show.matchedStreamingPlatforms }

    private var nextUp: Episode? {
        let today = Calendar.current.startOfDay(for: .now)
        return show.episodes
            .filter { $0.airDate >= today || $0.airDate == .distantFuture }
            .sorted {
                if $0.airDate == .distantFuture && $1.airDate == .distantFuture {
                    if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
                    return $0.episodeNumber < $1.episodeNumber
                }
                if $0.airDate == .distantFuture { return false }
                if $1.airDate == .distantFuture { return true }
                return $0.airDate < $1.airDate
            }
            .first
    }

    private var upcomingEpisodes: [Episode] {
        let today = Calendar.current.startOfDay(for: .now)
        return show.episodes
            .filter { $0.airDate > today || $0.airDate == .distantFuture }
            .sorted {
                if $0.airDate == .distantFuture && $1.airDate == .distantFuture {
                    if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
                    return $0.episodeNumber < $1.episodeNumber
                }
                if $0.airDate == .distantFuture { return false }
                if $1.airDate == .distantFuture { return true }
                return $0.airDate < $1.airDate
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroHeader
                    .padding(.bottom, DS.Spacing.lg)

                if let ep = nextUp {
                    nextUpCard(ep)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.lg)
                }

                if !upcomingEpisodes.isEmpty {
                    upcomingSection
                        .padding(.bottom, DS.Spacing.lg)
                }

                if nextUp == nil && upcomingEpisodes.isEmpty {
                    emptyState
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.lg)
                }

                whereToWatchSection

                if let overview = show.overview, !overview.isEmpty {
                    aboutSection(overview)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.xl)
                }

                if let error = refreshError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.lg)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Show") { showingEditShow = true }
                    if show.tmdbID != nil {
                        Button {
                            Task { await refreshEpisodes() }
                        } label: {
                            Label(isRefreshing ? "Refreshing…" : "Refresh Episodes", systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
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
                    Button(show.isSeen ? "Mark as Not Seen" : "Mark as Seen") {
                        show.isSeen.toggle()
                    }
                    Button(show.isArchived ? "Unarchive" : "Archive") {
                        show.isArchived.toggle()
                        show.updatedAt = .now
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .sheet(isPresented: $showingEditShow) {
            AddShowSheet(existingShow: show)
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            if let urlString = show.posterURL, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                    @unknown default:
                        Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .clipped()
            } else {
                Rectangle()
                    .foregroundStyle(DS.Color.imagePlaceholder)
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 340)

            VStack(alignment: .leading, spacing: 6) {
                Text(show.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let status = show.showStatus, !status.isEmpty {
                        Text(status)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    if !show.notificationsEnabled {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if show.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
        }
    }

    // MARK: - Next Up Card

    private func nextUpCard(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Next Up", systemImage: "play.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                Text(episode.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if episode.airDate == .distantFuture {
                        Text("TBA")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(episode.airDate.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(countdownLabel(for: episode.airDate))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Calendar.current.isDateInToday(episode.airDate) ? .orange : .primary)
                    }
                }
            }

            if !watchPlatforms.isEmpty {
                HStack(spacing: 6) {
                    ForEach(watchPlatforms.prefix(3), id: \.self) { platform in
                        if let url = platform.webURL {
                            Link(destination: url) {
                                Text(platform.rawValue)
                                    .statusBadge(color: platform.badgeColor)
                            }
                        } else {
                            Text(platform.rawValue)
                                .statusBadge(color: platform.badgeColor)
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Upcoming Episodes

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Upcoming Episodes")
                .font(.headline)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.sm)

            VStack(spacing: 0) {
                ForEach(Array(upcomingEpisodes.enumerated()), id: \.element.persistentModelID) { index, episode in
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(episode.displayTitle)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(episode.airDate == .distantFuture
                                     ? "TBA"
                                     : episode.airDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if episode.airDate != .distantFuture && Calendar.current.isDateInToday(episode.airDate) {
                                Text("Today")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, 11)

                        if index < upcomingEpisodes.count - 1 {
                            Divider()
                                .padding(.leading, DS.Spacing.lg)
                        }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: show.showStatus == "Ended" ? "checkmark.circle" : "calendar.badge.clock")
                .foregroundStyle(.secondary)
            Text(show.showStatus == "Ended" ? "All episodes have aired" : "No upcoming episodes scheduled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Where to Watch

    @ViewBuilder
    private var whereToWatchSection: some View {
        let providers = show.matchedStreamingPlatforms
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text("Where to Watch")
                    .font(.headline)
                HStack(spacing: 6) {
                    ForEach(providers) { platform in
                        Text(platform.rawValue)
                            .statusBadge(color: platform.badgeColor)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
        }
    }

    // MARK: - About

    private func aboutSection(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("About")
                .font(.headline)
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func countdownLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days > 0 { return "In \(days) days" }
        return ""
    }

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

// MARK: - Episode Row (kept for context menu use in NextUpView)

struct EpisodeRowView: View {
    let episode: Episode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.displayTitle)
                    .font(.subheadline)
                Text(episode.airDate == .distantFuture ? "TBA" : episode.airDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
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
        let show = Show(title: "Severance", platform: "Apple TV+", notes: "",
                        overview: "A thriller about work-life separation taken to the extreme.")
        container.mainContext.insert(show)
        let ep1 = Episode(seasonNumber: 3, episodeNumber: 1, title: "Hello, Ms. Cobel",
                          airDate: Calendar.current.date(byAdding: .day, value: 3, to: .now)!)
        ep1.show = show
        container.mainContext.insert(ep1)
        let ep2 = Episode(seasonNumber: 3, episodeNumber: 2, title: "The Grim Barbarity",
                          airDate: Calendar.current.date(byAdding: .day, value: 10, to: .now)!)
        ep2.show = show
        container.mainContext.insert(ep2)
        return NavigationStack {
            ShowDetailView(show: show)
        }
        .modelContainer(container)
    }
}
