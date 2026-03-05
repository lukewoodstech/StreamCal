import SwiftUI
import SwiftData

struct NextUpView: View {

    @Query(sort: \Show.title)
    private var shows: [Show]

    private var nextUpItems: [(show: Show, episode: Episode)] {
        shows
            .compactMap { show in
                guard let ep = show.nextUpcomingEpisode else { return nil }
                return (show, ep)
            }
            .sorted { $0.episode.airDate < $1.episode.airDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if nextUpItems.isEmpty {
                    ContentUnavailableView(
                        "Nothing Coming Up",
                        systemImage: "play.circle",
                        description: Text("Add shows and episodes to see what's next.")
                    )
                } else {
                    List(nextUpItems, id: \.episode.persistentModelID) { item in
                        NextUpRowView(show: item.show, episode: item.episode)
                    }
                }
            }
            .navigationTitle("Next Up")
        }
    }
}

struct NextUpRowView: View {
    let show: Show
    let episode: Episode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(show.title)
                    .font(.headline)
                Spacer()
                PlatformBadge(platform: show.platform)
            }
            Text(episode.displayTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .imageScale(.small)
                Text(episode.airDate, style: .date)
                    .font(.caption)
                if isToday(episode.airDate) {
                    Text("TODAY")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

#Preview {
    NextUpView()
        .modelContainer(previewContainer)
}

private var previewContainer: ModelContainer = {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Show.self, Episode.self, configurations: config)
    let ctx = container.mainContext
    let show1 = Show(title: "Severance", platform: "Apple TV+")
    ctx.insert(show1)
    let ep1 = Episode(seasonNumber: 2, episodeNumber: 3, title: "Woe's Hollow",
                      airDate: Calendar.current.date(byAdding: .day, value: 2, to: .now)!)
    ep1.show = show1
    ctx.insert(ep1)
    let show2 = Show(title: "The Bear", platform: "Hulu")
    ctx.insert(show2)
    let ep2 = Episode(seasonNumber: 3, episodeNumber: 1, title: "Premiere", airDate: .now)
    ep2.show = show2
    ctx.insert(ep2)
    return container
}()
