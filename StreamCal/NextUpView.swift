import SwiftUI
import SwiftData

struct NextUpView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Show.title)
    private var shows: [Show]

    private var activeShows: [Show] {
        shows.filter { !$0.isArchived }
    }

    // Episodes airing today (unwatched, future-dated)
    private var airingToday: [(show: Show, episode: Episode)] {
        activeShows.compactMap { show in
            guard let ep = show.nextUpcomingEpisode,
                  Calendar.current.isDateInToday(ep.airDate) else { return nil }
            return (show, ep)
        }
    }

    // Unwatched episodes that have already aired — watch backlog
    private var watchNext: [(show: Show, episode: Episode)] {
        activeShows.compactMap { show in
            guard let ep = show.nextToWatch,
                  ep.airDate != .distantFuture else { return nil }
            let today = Calendar.current.startOfDay(for: .now)
            guard ep.airDate <= today else { return nil }
            // Skip shows already represented in "Airing Today"
            guard !Calendar.current.isDateInToday(ep.airDate) else { return nil }
            return (show, ep)
        }.sorted {
            // Sort by season/episode so the user sees the right order
            if $0.show.title != $1.show.title { return $0.show.title < $1.show.title }
            if $0.episode.seasonNumber != $1.episode.seasonNumber { return $0.episode.seasonNumber < $1.episode.seasonNumber }
            return $0.episode.episodeNumber < $1.episode.episodeNumber
        }
    }

    // Future unwatched episodes (not today, not already aired)
    private var comingUp: [(show: Show, episode: Episode)] {
        let today = Calendar.current.startOfDay(for: .now)
        return activeShows.compactMap { show in
            guard let ep = show.nextUpcomingEpisode,
                  ep.airDate > today,
                  !Calendar.current.isDateInToday(ep.airDate) else { return nil }
            return (show, ep)
        }.sorted { $0.episode.airDate < $1.episode.airDate }
    }

    // Shows fully caught up: all episodes watched or no episodes at all
    private var caughtUpShows: [Show] {
        activeShows.filter { show in
            show.nextToWatch == nil && !show.episodes.isEmpty
        }
    }

    private var hasAnything: Bool {
        !airingToday.isEmpty || !watchNext.isEmpty || !comingUp.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeShows.isEmpty {
                    ContentUnavailableView(
                        "No Shows Yet",
                        systemImage: "play.circle",
                        description: Text("Add shows from the Library tab to start tracking.")
                    )
                } else if !hasAnything {
                    allCaughtUpView
                } else {
                    list
                }
            }
            .navigationTitle("Next Up")
        }
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

                if !caughtUpShows.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Following")
                            .font(.headline)
                            .padding(.horizontal)
                        ForEach(caughtUpShows) { show in
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

    // MARK: - List

    private var list: some View {
        List {
            if !airingToday.isEmpty {
                Section {
                    ForEach(airingToday, id: \.episode.persistentModelID) { item in
                        NextUpRowView(show: item.show, episode: item.episode)
                    }
                } header: {
                    Label("Airing Today", systemImage: "star.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .textCase(nil)
                }
            }

            if !watchNext.isEmpty {
                Section {
                    ForEach(watchNext, id: \.episode.persistentModelID) { item in
                        NextUpRowView(show: item.show, episode: item.episode)
                    }
                } header: {
                    Label("Watch Next", systemImage: "play.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .textCase(nil)
                }
            }

            if !comingUp.isEmpty {
                Section {
                    ForEach(comingUp, id: \.episode.persistentModelID) { item in
                        NextUpRowView(show: item.show, episode: item.episode)
                    }
                } header: {
                    Text("Coming Up")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .textCase(nil)
                }
            }

            if !caughtUpShows.isEmpty {
                Section {
                    ForEach(caughtUpShows) { show in
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

    private var posterURL: URL? {
        guard let s = show.posterURL else { return nil }
        return URL(string: s)
    }

    private var isTBA: Bool { episode.airDate == .distantFuture }
    private var isToday: Bool { Calendar.current.isDateInToday(episode.airDate) }
    private var isAvailableNow: Bool {
        !isTBA && episode.airDate <= Calendar.current.startOfDay(for: .now)
    }
    private var daysUntil: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: episode.airDate)
        ).day ?? 0
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

                HStack(spacing: 6) {
                    if isToday {
                        Label("Airing Today", systemImage: "star.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    } else if isAvailableNow {
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
                        if daysUntil <= 7 {
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
        .padding(.vertical, 4)
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
                Text(statusText(for: show))
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

    private func statusText(for show: Show) -> String {
        if let status = show.showStatus {
            if status == "Ended" || status == "Canceled" {
                return status
            }
        }
        return "No upcoming episodes"
    }
}

// MARK: - Preview

#Preview {
    NextUpView()
        .modelContainer(previewContainer)
}

private var previewContainer: ModelContainer = {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Show.self, Episode.self, configurations: config)
    let ctx = container.mainContext

    let show1 = Show(title: "Severance", platform: "Apple TV+",
                     overview: "A thriller about work-life separation.", showStatus: "Returning Series")
    ctx.insert(show1)
    let ep1 = Episode(seasonNumber: 2, episodeNumber: 4, title: "Woe's Hollow",
                      airDate: Calendar.current.date(byAdding: .day, value: 0, to: .now)!)
    ep1.show = show1
    ctx.insert(ep1)

    let show2 = Show(title: "The Bear", platform: "Hulu", showStatus: "Returning Series")
    ctx.insert(show2)
    let ep2 = Episode(seasonNumber: 3, episodeNumber: 1, title: "Tomorrow",
                      airDate: Calendar.current.date(byAdding: .day, value: 5, to: .now)!)
    ep2.show = show2
    ctx.insert(ep2)

    let show3 = Show(title: "Andor", platform: "Disney+", showStatus: "Ended")
    ctx.insert(show3)
    let ep3 = Episode(seasonNumber: 2, episodeNumber: 12, title: "Finale",
                      airDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
                      isWatched: true)
    ep3.show = show3
    ctx.insert(ep3)

    return container
}()
