import SwiftUI
import SwiftData

struct CalendarView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Episode.airDate)
    private var allEpisodes: [Episode]

    private var calendarDays: [WatchPlanner.CalendarDay] {
        WatchPlanner.calendarDays(from: allEpisodes)
    }

    var body: some View {
        NavigationStack {
            Group {
                if calendarDays.isEmpty {
                    ContentUnavailableView(
                        "Nothing Scheduled",
                        systemImage: "calendar.badge.clock",
                        description: Text("Add shows to your library to see upcoming episodes.")
                    )
                } else {
                    calendarList
                }
            }
            .navigationTitle("Release Radar")
        }
    }

    private var calendarList: some View {
        List {
            ForEach(calendarDays, id: \.date) { day in
                Section {
                    ForEach(day.episodes) { episode in
                        CalendarEpisodeRow(episode: episode)
                    }
                } header: {
                    CalendarDayHeader(day: day)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await RefreshService.shared.refreshAllShows(modelContext: modelContext)
        }
    }
}

// MARK: - Day Header

struct CalendarDayHeader: View {
    let day: WatchPlanner.CalendarDay

    private var label: String {
        let cal = Calendar.current
        if day.isToday { return "Today" }
        if cal.isDateInTomorrow(day.date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: day.date)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(day.isToday ? Color.accentColor : .primary)

            if day.isToday {
                Text("TODAY")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }

            Spacer()

            Text("\(day.episodes.count) ep\(day.episodes.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Calendar Episode Row

struct CalendarEpisodeRow: View {
    @Bindable var episode: Episode

    private var show: Show? { episode.show }

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var isPast: Bool { episode.airDate < today }
    private var isToday: Bool { cal.isDateInToday(episode.airDate) }

    private var planLabel: String? {
        guard let d = episode.plannedDate else { return nil }
        if cal.isDateInToday(d) { return "Tonight" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Watched indicator strip
            RoundedRectangle(cornerRadius: 2)
                .frame(width: 3)
                .foregroundStyle(
                    episode.isWatched ? Color.green :
                    isToday ? Color.orange :
                    isPast ? Color.blue :
                    Color.clear
                )
                .frame(height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(show?.title ?? "Unknown Show")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(episode.isWatched ? .secondary : .primary)
                Text(episode.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                if episode.isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                } else if let plan = planLabel {
                    Text(plan)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.indigo)
                        .clipShape(Capsule())
                } else if isPast {
                    Text("Unwatched")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let show {
                EpisodeContextMenuItems(episode: episode, show: show)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                episode.isWatched.toggle()
                episode.plannedDate = nil
                if let show {
                    Task { await NotificationService.shared.scheduleNotifications(for: show) }
                }
            } label: {
                Label(
                    episode.isWatched ? "Unwatch" : "Watched",
                    systemImage: episode.isWatched ? "eye.slash" : "checkmark"
                )
            }
            .tint(episode.isWatched ? .gray : .green)
        }
        .swipeActions(edge: .trailing) {
            Button {
                WatchPlanner.planTonight(episode)
            } label: {
                Label("Tonight", systemImage: "moon.stars.fill")
            }
            .tint(.indigo)
        }
    }
}

// MARK: - Preview

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
    let show3 = Show(title: "The Last of Us", platform: "Max")
    ctx.insert(show3)

    for i in -3..<12 {
        let showIdx = i % 3
        let show = showIdx == 0 ? show1 : showIdx == 1 ? show2 : show3
        let ep = Episode(
            seasonNumber: 2,
            episodeNumber: abs(i) + 1,
            title: "Episode \(abs(i) + 1)",
            airDate: Calendar.current.date(byAdding: .day, value: i * 2, to: .now)!
        )
        ep.show = show
        if i < -1 { ep.isWatched = true }
        ctx.insert(ep)
    }
    return container
}()
