import SwiftUI
import SwiftData

struct NextUpView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Show.title)
    private var shows: [Show]

    private var activeShows: [Show] { shows.filter { !$0.isArchived } }

    // Future-release sections only — no backlog or progress content
    private var airingToday: [(show: Show, episode: Episode)] { WatchPlanner.nextUpAiringToday(from: shows) }
    private var thisWeek: [(show: Show, episode: Episode)] { WatchPlanner.nextUpThisWeek(from: shows) }
    private var comingSoon: [(show: Show, episode: Episode)] { WatchPlanner.nextUpComingSoon(from: shows) }
    private var dateTBA: [(show: Show, episode: Episode)] { WatchPlanner.nextUpDateTBA(from: shows) }

    private var hasUpcomingContent: Bool {
        !airingToday.isEmpty || !thisWeek.isEmpty || !comingSoon.isEmpty || !dateTBA.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeShows.isEmpty {
                    emptyLibraryState
                } else if !hasUpcomingContent {
                    noUpcomingView
                } else {
                    list
                }
            }
            .navigationTitle("Next Up")
        }
    }

    // MARK: - Empty library state

    private var emptyLibraryState: some View {
        ContentUnavailableView(
            "No Shows Yet",
            systemImage: "play.circle",
            description: Text("Add shows from the Library tab to start tracking.")
        )
    }

    // MARK: - No Upcoming Episodes

    private var noUpcomingView: some View {
        ContentUnavailableView(
            "No Upcoming Episodes",
            systemImage: "calendar",
            description: Text("Nothing scheduled yet.\nCheck back when new episodes are announced.")
        )
        .refreshable {
            await RefreshService.shared.refreshAllShows(modelContext: modelContext)
        }
    }

    // MARK: - Main list

    private var list: some View {
        List {
            if !airingToday.isEmpty {
                Section {
                    ForEach(airingToday, id: \.episode.persistentModelID) { item in
                        EpisodeCard(show: item.show, episode: item.episode)
                            .swipeActions(edge: .leading) {
                                watchedButton(item.episode, item.show)
                            }
                            .swipeActions(edge: .trailing) {
                                planTonightButton(item.episode, item.show)
                            }
                    }
                } header: {
                    NextUpSectionHeader(title: "Airing Today", icon: "star.fill", color: .orange)
                }
            }

            if !thisWeek.isEmpty {
                Section {
                    ForEach(thisWeek, id: \.episode.persistentModelID) { item in
                        EpisodeCard(show: item.show, episode: item.episode)
                            .swipeActions(edge: .leading) {
                                watchedButton(item.episode, item.show)
                            }
                            .swipeActions(edge: .trailing) {
                                planTonightButton(item.episode, item.show)
                            }
                    }
                } header: {
                    NextUpSectionHeader(title: "This Week", icon: "calendar", color: .blue)
                }
            }

            if !comingSoon.isEmpty {
                Section {
                    ForEach(comingSoon, id: \.episode.persistentModelID) { item in
                        EpisodeCard(show: item.show, episode: item.episode)
                            .swipeActions(edge: .leading) {
                                watchedButton(item.episode, item.show)
                            }
                            .swipeActions(edge: .trailing) {
                                planTonightButton(item.episode, item.show)
                            }
                    }
                } header: {
                    NextUpSectionHeader(title: "Coming Soon", icon: "clock", color: .secondary)
                }
            }

            if !dateTBA.isEmpty {
                Section {
                    ForEach(dateTBA, id: \.episode.persistentModelID) { item in
                        EpisodeCard(show: item.show, episode: item.episode)
                            .swipeActions(edge: .leading) {
                                watchedButton(item.episode, item.show)
                            }
                    }
                } header: {
                    NextUpSectionHeader(title: "Date TBA", icon: "calendar.badge.clock", color: .secondary)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await RefreshService.shared.refreshAllShows(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func watchedButton(_ episode: Episode, _ show: Show) -> some View {
        Button {
            episode.isWatched = true
            episode.plannedDate = nil
            Task { await NotificationService.shared.scheduleNotifications(for: show) }
        } label: {
            Label("Watched", systemImage: "checkmark")
        }
        .tint(.green)
    }

    @ViewBuilder
    private func planTonightButton(_ episode: Episode, _ show: Show) -> some View {
        Button {
            WatchPlanner.planTonight(episode)
            Task { await NotificationService.shared.scheduleNotifications(for: show) }
        } label: {
            Label("Tonight", systemImage: "moon.stars.fill")
        }
        .tint(.indigo)
    }
}

// MARK: - Section Header

struct NextUpSectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .imageScale(.small)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.top, 24)
        .padding(.bottom, 10)
    }
}

// MARK: - Episode Card

struct EpisodeCard: View {
    let show: Show
    @Bindable var episode: Episode

    private var posterURL: URL? {
        guard let s = show.posterURL else { return nil }
        return URL(string: s)
    }

    private var cal: Calendar { Calendar.current }

    private var isTBA: Bool { episode.airDate == .distantFuture }
    private var isToday: Bool { cal.isDateInToday(episode.airDate) }
    private var isPlannedToday: Bool { episode.isPlannedToday }

    private var daysUntil: Int {
        let today = cal.startOfDay(for: .now)
        return cal.dateComponents([.day], from: today, to: cal.startOfDay(for: episode.airDate)).day ?? 0
    }

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.tertiary)
                        }
                @unknown default:
                    Rectangle().foregroundStyle(Color(.systemGray5))
                }
            }
            .frame(width: 54, height: 81)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(show.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    PlatformBadge(platform: show.platform)
                }

                Text(episode.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                statusBadge
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu { EpisodeContextMenuItems(episode: episode, show: show) }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isPlannedToday {
            Label("Planned tonight", systemImage: "moon.stars.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.indigo)
        } else if isToday {
            Label("New today", systemImage: "star.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
        } else if isTBA {
            Label("Date TBA", systemImage: "calendar.badge.clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                Text(episode.airDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if daysUntil > 0 && daysUntil <= 7 {
                    Text("in \(daysUntil)d")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Episode Context Menu Items (reusable)

struct EpisodeContextMenuItems: View {
    let episode: Episode
    let show: Show

    var body: some View {
        Group {
            Button {
                episode.isWatched.toggle()
                if episode.isWatched { episode.plannedDate = nil }
                Task { await NotificationService.shared.scheduleNotifications(for: show) }
            } label: {
                Label(
                    episode.isWatched ? "Mark Unwatched" : "Mark Watched",
                    systemImage: episode.isWatched ? "eye.slash" : "checkmark.circle"
                )
            }

            Divider()

            Button {
                WatchPlanner.planTonight(episode)
                Task { await NotificationService.shared.scheduleNotifications(for: show) }
            } label: {
                Label("Watch Tonight", systemImage: "moon.stars")
            }

            Button {
                WatchPlanner.planTomorrow(episode)
                Task { await NotificationService.shared.scheduleNotifications(for: show) }
            } label: {
                Label("Watch Tomorrow", systemImage: "sunrise")
            }

            Button {
                WatchPlanner.planThisWeekend(episode)
                Task { await NotificationService.shared.scheduleNotifications(for: show) }
            } label: {
                Label("Watch This Weekend", systemImage: "calendar.badge.clock")
            }

            if episode.plannedDate != nil {
                Button(role: .destructive) {
                    WatchPlanner.clearPlan(for: episode)
                    Task { await NotificationService.shared.scheduleNotifications(for: show) }
                } label: {
                    Label("Clear Plan", systemImage: "xmark.circle")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NextUpView()
        .modelContainer(nextUpPreviewContainer)
        .background(Color(.systemGroupedBackground))
}

private var nextUpPreviewContainer: ModelContainer = {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Show.self, Episode.self, configurations: config)
    let ctx = container.mainContext
    let cal = Calendar.current

    // Airing Today
    let show1 = Show(title: "Severance", platform: "Apple TV+", showStatus: "Returning Series")
    ctx.insert(show1)
    let ep1 = Episode(seasonNumber: 2, episodeNumber: 4, title: "Woe's Hollow",
                      airDate: cal.startOfDay(for: .now))
    ep1.show = show1
    ctx.insert(ep1)

    // This Week
    let show2 = Show(title: "The Last of Us", platform: "Max", showStatus: "Returning Series")
    ctx.insert(show2)
    let ep2 = Episode(seasonNumber: 2, episodeNumber: 3, title: "Through the Valley",
                      airDate: cal.date(byAdding: .day, value: 3, to: .now)!)
    ep2.show = show2
    ctx.insert(ep2)

    let show3 = Show(title: "White Lotus", platform: "Max", showStatus: "Returning Series")
    ctx.insert(show3)
    let ep3 = Episode(seasonNumber: 3, episodeNumber: 2, title: "Episode 2",
                      airDate: cal.date(byAdding: .day, value: 5, to: .now)!)
    ep3.show = show3
    ctx.insert(ep3)

    // Coming Soon
    let show4 = Show(title: "Andor", platform: "Disney+", showStatus: "Returning Series")
    ctx.insert(show4)
    let ep4 = Episode(seasonNumber: 2, episodeNumber: 1, title: "Aftermath",
                      airDate: cal.date(byAdding: .day, value: 18, to: .now)!)
    ep4.show = show4
    ctx.insert(ep4)

    // TBA
    let show5 = Show(title: "Succession", platform: "Max", showStatus: "Ended")
    ctx.insert(show5)
    let ep5 = Episode(seasonNumber: 5, episodeNumber: 1, title: "TBA", airDate: .distantFuture)
    ep5.show = show5
    ctx.insert(ep5)

    return container
}()
