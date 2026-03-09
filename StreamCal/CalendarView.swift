import SwiftUI
import SwiftData

struct CalendarView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Episode.airDate)
    private var allEpisodes: [Episode]

    private var calendar: Calendar { Calendar.current }

    /// Show 7 days back through 60 days forward — gives context on recent airings
    /// and a meaningful look-ahead window.
    private var windowEpisodes: [Episode] {
        let today = calendar.startOfDay(for: .now)
        guard
            let start = calendar.date(byAdding: .day, value: -7, to: today),
            let end = calendar.date(byAdding: .day, value: 60, to: today)
        else { return [] }
        return allEpisodes.filter {
            $0.airDate != .distantFuture && $0.airDate >= start && $0.airDate < end
        }
    }

    /// Episodes grouped by their calendar day, sorted ascending.
    private var groupedByDay: [(date: Date, episodes: [Episode])] {
        var dict: [Date: [Episode]] = [:]
        for ep in windowEpisodes {
            let day = calendar.startOfDay(for: ep.airDate)
            dict[day, default: []].append(ep)
        }
        return dict
            .map { (date: $0.key, episodes: $0.value.sorted { $0.show?.title ?? "" < $1.show?.title ?? "" }) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groupedByDay.isEmpty {
                    ContentUnavailableView(
                        "Nothing Scheduled",
                        systemImage: "calendar.badge.clock",
                        description: Text("Add shows to your library to see upcoming episodes.")
                    )
                } else {
                    List {
                        ForEach(groupedByDay, id: \.date) { group in
                            Section(header: DayHeaderView(date: group.date)) {
                                ForEach(group.episodes) { episode in
                                    CalendarEpisodeRowView(episode: episode)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await RefreshService.shared.refreshAllShows(modelContext: modelContext)
                    }
                }
            }
            .navigationTitle("Calendar")
        }
    }
}

struct DayHeaderView: View {
    let date: Date

    var body: some View {
        HStack {
            Text(date, style: .date)
                .font(.subheadline)
                .fontWeight(.semibold)
            if Calendar.current.isDateInToday(date) {
                Text("TODAY")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
    }
}

struct CalendarEpisodeRowView: View {
    let episode: Episode

    private var isInPast: Bool {
        episode.airDate < Calendar.current.startOfDay(for: .now)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                if let showTitle = episode.show?.title {
                    Text(showTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(episode.isWatched ? .secondary : .primary)
                }
                Text(episode.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if episode.isWatched {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.small)
            } else if isInPast {
                Text("Unwatched")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 1)
    }
}

#Preview {
    CalendarView()
        .modelContainer(calendarPreviewContainer)
}

private var calendarPreviewContainer: ModelContainer = {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Show.self, Episode.self, configurations: config)
    let ctx = container.mainContext
    let show1 = Show(title: "Severance", platform: "Apple TV+")
    ctx.insert(show1)
    let show2 = Show(title: "The Bear", platform: "Hulu")
    ctx.insert(show2)
    for i in 0..<10 {
        let ep = Episode(
            seasonNumber: 2, episodeNumber: i + 1, title: "Episode \(i + 1)",
            airDate: Calendar.current.date(byAdding: .day, value: i * 3, to: .now)!
        )
        ep.show = i % 2 == 0 ? show1 : show2
        ctx.insert(ep)
    }
    return container
}()
