import SwiftUI
import SwiftData

struct NextUpView: View {

    @Query(sort: \Show.title)
    private var shows: [Show]

    private var activeShows: [Show] {
        shows.filter { !$0.isArchived }
    }

    private var nextUpItems: [(show: Show, episode: Episode)] {
        activeShows
            .compactMap { show in
                guard let ep = show.nextUpcomingEpisode else { return nil }
                return (show, ep)
            }
            .sorted { $0.episode.airDate < $1.episode.airDate }
    }

    /// Shows that are tracked but have no upcoming episodes (caught up or ended).
    private var caughtUpShows: [Show] {
        activeShows.filter { show in
            show.nextUpcomingEpisode == nil && !show.episodes.isEmpty
        }
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
                } else if nextUpItems.isEmpty {
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
                    Text("No upcoming episodes right now.\nCheck back after new episodes air.")
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
    }

    // MARK: - List

    private var list: some View {
        List {
            // "Airing Today" section
            let today = nextUpItems.filter { Calendar.current.isDateInToday($0.episode.airDate) }
            let upcoming = nextUpItems.filter { !Calendar.current.isDateInToday($0.episode.airDate) }

            if !today.isEmpty {
                Section {
                    ForEach(today, id: \.episode.persistentModelID) { item in
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

            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming, id: \.episode.persistentModelID) { item in
                        NextUpRowView(show: item.show, episode: item.episode)
                    }
                } header: {
                    if !today.isEmpty {
                        Text("Coming Up")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .textCase(nil)
                    }
                }
            }

            // Caught-up shows at the bottom as a collapsed hint
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

    private var isToday: Bool {
        Calendar.current.isDateInToday(episode.airDate)
    }

    private var daysUntil: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: episode.airDate)).day ?? 0
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
                        Label("Today", systemImage: "star.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
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
