import SwiftUI
import SwiftData

struct NextUpView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Show.title)
    private var shows: [Show]

    private var activeShows: [Show] { shows.filter { !$0.isArchived } }

    // Derived sections via WatchPlanner
    private var tonightsPlan: [(show: Show, episode: Episode)] { WatchPlanner.tonightsPlan(from: shows) }
    private var continueWatching: [(show: Show, episode: Episode)] { WatchPlanner.continueWatching(from: shows) }
    private var newToday: [(show: Show, episode: Episode)] { WatchPlanner.newEpisodesToday(from: shows) }
    private var comingSoon: [(show: Show, episode: Episode)] { WatchPlanner.comingSoon(from: shows) }
    private var caughtUp: [Show] { WatchPlanner.caughtUpShows(from: shows) }

    private var hasActionableContent: Bool {
        !tonightsPlan.isEmpty || !continueWatching.isEmpty || !newToday.isEmpty || !comingSoon.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeShows.isEmpty {
                    emptyLibraryState
                } else if !hasActionableContent {
                    allCaughtUpView
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

    // MARK: - All Caught Up

    private var allCaughtUpView: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.green)
                    Text("All Caught Up")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("You're up to date on everything.\nCheck back when new episodes air.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)

                if !caughtUp.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Following")
                            .font(.headline)
                            .padding(.horizontal)
                        ForEach(caughtUp) { show in
                            CaughtUpRowView(show: show)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable {
            await RefreshService.shared.refreshAllShows(modelContext: modelContext)
        }
    }

    // MARK: - Main list

    private var list: some View {
        List {
            // Tonight's Plan — episodes the user explicitly scheduled for today
            if !tonightsPlan.isEmpty {
                Section {
                    ForEach(tonightsPlan, id: \.episode.persistentModelID) { item in
                        NextUpRowView(show: item.show, episode: item.episode)
                    }
                } header: {
                    Label("Tonight's Plan", systemImage: "moon.stars.fill")
                        .foregroundStyle(.indigo)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .textCase(nil)
                }
            }

            // New Episodes Today — episodes releasing today
            if !newToday.isEmpty {
                Section {
                    ForEach(newToday, id: \.episode.persistentModelID) { item in
                        NextUpRowView(show: item.show, episode: item.episode)
                    }
                } header: {
                    Label("New Today", systemImage: "star.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .textCase(nil)
                }
            }

            // Continue Watching — next unwatched aired episode per show (backlog)
            if !continueWatching.isEmpty {
                Section {
                    ForEach(continueWatching, id: \.episode.persistentModelID) { item in
                        NextUpRowView(show: item.show, episode: item.episode)
                    }
                } header: {
                    Label("Continue Watching", systemImage: "play.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .textCase(nil)
                }
            }

            // Coming Soon — upcoming episodes in the next 7 days
            if !comingSoon.isEmpty {
                Section {
                    ForEach(comingSoon, id: \.episode.persistentModelID) { item in
                        NextUpRowView(show: item.show, episode: item.episode)
                    }
                } header: {
                    Text("Coming Soon")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .textCase(nil)
                }
            }

            // Caught up shows — dimmed at the bottom
            if !caughtUp.isEmpty {
                Section {
                    ForEach(caughtUp) { show in
                        CaughtUpRowView(show: show)
                    }
                } header: {
                    Text("All Caught Up")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .textCase(nil)
                }
            }
        }
        .refreshable {
            await RefreshService.shared.refreshAllShows(modelContext: modelContext)
        }
    }
}

// MARK: - Next Up Row

struct NextUpRowView: View {
    let show: Show
    let episode: Episode

    @Environment(\.modelContext) private var modelContext

    private var posterURL: URL? {
        guard let s = show.posterURL else { return nil }
        return URL(string: s)
    }

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }

    private var isTBA: Bool { episode.airDate == .distantFuture }
    private var isToday: Bool { cal.isDateInToday(episode.airDate) }
    private var isBacklog: Bool { !isTBA && episode.airDate <= today }
    private var isPlannedToday: Bool { episode.isPlannedToday }

    private var daysUntil: Int {
        cal.dateComponents([.day], from: today, to: cal.startOfDay(for: episode.airDate)).day ?? 0
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                @unknown default:
                    Rectangle().foregroundStyle(Color(.systemGray5))
                }
            }
            .frame(width: 46, height: 69)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(show.title)
                        .font(.headline)
                    Spacer()
                    PlatformBadge(platform: show.platform)
                }

                Text(episode.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                statusLabel
            }
        }
        .padding(.vertical, 4)
        .contextMenu { episodeContextMenu }
        .swipeActions(edge: .leading) {
            Button {
                episode.isWatched = true
                episode.plannedDate = nil
                Task { await NotificationService.shared.scheduleNotifications(for: show) }
            } label: {
                Label("Watched", systemImage: "checkmark")
            }
            .tint(.green)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: 6) {
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
            } else if isBacklog {
                Label("Available now", systemImage: "play.circle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            } else if isTBA {
                Label("Date TBA", systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
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

    @ViewBuilder
    private var episodeContextMenu: some View {
        EpisodeContextMenuItems(episode: episode, show: show)
    }
}

// MARK: - Caught Up Row

struct CaughtUpRowView: View {
    let show: Show

    private var posterURL: URL? {
        guard let s = show.posterURL else { return nil }
        return URL(string: s)
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                @unknown default:
                    Rectangle().foregroundStyle(Color(.systemGray5))
                }
            }
            .frame(width: 36, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .opacity(0.6)

            VStack(alignment: .leading, spacing: 3) {
                Text(show.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(caughtUpStatusText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green.opacity(0.7))
                .imageScale(.small)
        }
        .padding(.vertical, 2)
    }

    private var caughtUpStatusText: String {
        if let status = show.showStatus, status == "Ended" || status == "Canceled" {
            return status
        }
        if let next = show.nextUpcomingEpisode {
            if next.airDate == .distantFuture { return "Next episode TBA" }
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE MMM d"
            return "Next: \(formatter.string(from: next.airDate))"
        }
        return "Up to date"
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
            } label: {
                Label("Watch Tonight", systemImage: "moon.stars")
            }

            Button {
                WatchPlanner.planTomorrow(episode)
            } label: {
                Label("Watch Tomorrow", systemImage: "sunrise")
            }

            Button {
                WatchPlanner.planThisWeekend(episode)
            } label: {
                Label("Watch This Weekend", systemImage: "calendar.badge.clock")
            }

            if episode.plannedDate != nil {
                Button(role: .destructive) {
                    WatchPlanner.clearPlan(for: episode)
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
}

private var nextUpPreviewContainer: ModelContainer = {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Show.self, Episode.self, configurations: config)
    let ctx = container.mainContext

    let show1 = Show(title: "Severance", platform: "Apple TV+", showStatus: "Returning Series")
    ctx.insert(show1)
    let ep1 = Episode(seasonNumber: 2, episodeNumber: 4, title: "Woe's Hollow",
                      airDate: Calendar.current.date(byAdding: .day, value: 0, to: .now)!)
    ep1.show = show1
    ctx.insert(ep1)

    let show2 = Show(title: "The Bear", platform: "Hulu", showStatus: "Returning Series")
    ctx.insert(show2)
    let ep2 = Episode(seasonNumber: 3, episodeNumber: 1, title: "Tomorrow",
                      airDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)!)
    ep2.show = show2
    ctx.insert(ep2)

    let show3 = Show(title: "The Last of Us", platform: "Max", showStatus: "Returning Series")
    ctx.insert(show3)
    let ep3 = Episode(seasonNumber: 2, episodeNumber: 3, title: "Episode 3",
                      airDate: Calendar.current.date(byAdding: .day, value: 4, to: .now)!)
    ep3.show = show3
    ep3.plannedDate = Calendar.current.startOfDay(for: .now)
    ctx.insert(ep3)

    return container
}()
