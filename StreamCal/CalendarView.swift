import SwiftUI
import SwiftData

struct CalendarView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Episode.airDate)
    private var allEpisodes: [Episode]

    @Query(sort: \Movie.theatricalReleaseDate)
    private var allMovies: [Movie]

    @Query(sort: \SportGame.gameDate)
    private var allGames: [SportGame]

    @Query(sort: \AnimeEpisode.airDate)
    private var allAnimeEpisodes: [AnimeEpisode]

    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    @EnvironmentObject private var purchaseService: PurchaseService
    @State private var showingAskStreamCal: Bool = false

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }

    private var calendarDays: [WatchPlanner.CalendarDay] {
        WatchPlanner.calendarDays(from: allEpisodes, movies: allMovies, games: allGames, anime: allAnimeEpisodes)
    }

    // O(1) lookup: midnight-local date → CalendarDay
    private var daysByDate: [Date: WatchPlanner.CalendarDay] {
        Dictionary(uniqueKeysWithValues: calendarDays.map { ($0.date, $0) })
    }

    // Legacy alias for MonthGridView episode dots
    private var episodesByDate: [Date: [Episode]] {
        daysByDate.mapValues { $0.episodes }
    }

    /// Cap forward navigation at the month of the last known event, or 24 months out — whichever is later.
    private var latestContentMonth: Date {
        let latest = calendarDays.last?.date ?? today
        let cap = cal.date(byAdding: .month, value: 24, to: today) ?? today
        return cal.startOfMonth(for: max(latest, cap))
    }

    private var selectedDay: WatchPlanner.CalendarDay? { daysByDate[selectedDate] }
    private var selectedEpisodes: [Episode] { selectedDay?.episodes ?? [] }
    private var selectedMovies: [Movie] { selectedDay?.movies ?? [] }
    private var selectedGames: [SportGame] { selectedDay?.games ?? [] }
    private var selectedAnimeEpisodes: [AnimeEpisode] { selectedDay?.animeEpisodes ?? [] }
    private var selectedHasContent: Bool { !(selectedDay?.isEmpty ?? true) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed month grid — does not scroll
                MonthGridView(
                    displayedMonth: $displayedMonth,
                    selectedDate: $selectedDate,
                    episodesByDate: episodesByDate,
                    moviesByDate: daysByDate.mapValues { $0.movies },
                    gamesByDate: daysByDate.mapValues { $0.games },
                    animeByDate: daysByDate.mapValues { $0.animeEpisodes },
                    today: today,
                    maxMonth: latestContentMonth,
                    onMonthChanged: { newMonth in
                        selectedDate = nearestDate(in: newMonth, from: episodesByDate) ?? cal.startOfMonth(for: newMonth)
                    },
                    onGoToToday: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            displayedMonth = cal.startOfMonth(for: today)
                            selectedDate = today
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .background(Color(.systemGroupedBackground))

                Divider()

                // Scrollable day content
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        if selectedDate < today {
                            pastDayState
                                .padding(.top, 40)
                        } else if !selectedHasContent {
                            emptyDayState
                                .padding(.top, 40)
                        } else {
                            dayPaneHeader
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .padding(.bottom, 4)

                            if !selectedEpisodes.isEmpty {
                                dayContentCard(label: "TV Shows") {
                                    ForEach(Array(selectedEpisodes.enumerated()), id: \.element.persistentModelID) { index, episode in
                                        CalendarEpisodeRow(episode: episode)
                                            .padding(.horizontal, 16)
                                        if index < selectedEpisodes.count - 1 {
                                            Divider().padding(.leading, 74)
                                        }
                                    }
                                }
                            }

                            if !selectedMovies.isEmpty {
                                dayContentCard(label: "Movies") {
                                    ForEach(Array(selectedMovies.enumerated()), id: \.element.persistentModelID) { index, movie in
                                        NavigationLink(destination: MovieDetailView(movie: movie)) {
                                            CalendarMovieRow(movie: movie)
                                                .padding(.horizontal, 16)
                                        }
                                        .buttonStyle(.plain)
                                        if index < selectedMovies.count - 1 {
                                            Divider().padding(.leading, 74)
                                        }
                                    }
                                }
                            }

                            if !selectedGames.isEmpty {
                                dayContentCard(label: "Games") {
                                    ForEach(Array(selectedGames.enumerated()), id: \.element.persistentModelID) { index, game in
                                        CalendarGameRow(game: game)
                                            .padding(.horizontal, 16)
                                        if index < selectedGames.count - 1 {
                                            Divider().padding(.leading, 74)
                                        }
                                    }
                                }
                            }

                            if !selectedAnimeEpisodes.isEmpty {
                                dayContentCard(label: "Anime") {
                                    ForEach(Array(selectedAnimeEpisodes.enumerated()), id: \.element.persistentModelID) { index, ep in
                                        CalendarAnimeRow(episode: ep)
                                            .padding(.horizontal, 16)
                                        if index < selectedAnimeEpisodes.count - 1 {
                                            Divider().padding(.leading, 74)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .background(Color(.systemGroupedBackground))
                .refreshable { await refreshAll() }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Wordmark()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAskStreamCal = true } label: {
                        Image(systemName: "sparkles")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(DS.Color.ai)
                    }
                }
            }
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .sheet(isPresented: $showingAskStreamCal) {
                AskStreamCalView().environmentObject(purchaseService)
            }
            .onAppear {
                selectedDate = nearestDate(from: today, in: episodesByDate) ?? today
            }
            .onChange(of: episodesByDate.keys.count) {
                if !selectedHasContent {
                    selectedDate = nearestDate(from: today, in: episodesByDate) ?? today
                }
            }
        }
    }

    @ViewBuilder
    private func dayContentCard<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                content()
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    private var pastDayState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("This Day Has Passed")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Future episodes, movies, and games will appear here once scheduled.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Go to Today") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    displayedMonth = cal.startOfMonth(for: today)
                    selectedDate = today
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var calendarIsEmpty: Bool {
        allEpisodes.isEmpty && allMovies.isEmpty && allGames.isEmpty && allAnimeEpisodes.isEmpty
    }

    private var emptyDayState: some View {
        VStack(spacing: 10) {
            if calendarIsEmpty {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Nothing Here Yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Add shows, movies, or teams from your **Library** to fill up your calendar.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Nothing Scheduled")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("No episodes, releases, or games on this day.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Returns today if it has episodes, otherwise the next calendar day that does.
    private func nearestDate(from start: Date, in dict: [Date: [Episode]]) -> Date? {
        let sorted = dict.keys.filter { $0 >= start }.sorted()
        return sorted.first
    }

    /// Returns the first day in `month` that has episodes, or nil if none.
    private func nearestDate(in month: Date, from dict: [Date: [Episode]]) -> Date? {
        let monthStart = cal.startOfMonth(for: month)
        guard let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return nil }
        let sorted = dict.keys.filter { $0 >= monthStart && $0 < monthEnd }.sorted()
        return sorted.first
    }

    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await RefreshService.shared.refreshAllShows(modelContext: modelContext) }
            group.addTask { await RefreshService.shared.refreshAllMovies(modelContext: modelContext) }
            group.addTask { await RefreshService.shared.refreshAllTeams(modelContext: modelContext) }
            group.addTask { await RefreshService.shared.refreshAllAnime(modelContext: modelContext) }
        }
    }

    private var dayPaneHeader: some View {
        HStack {
            Text(headerLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(cal.isDateInToday(selectedDate) ? Color.accentColor : .primary)
            let parts: [String] = [
                selectedEpisodes.isEmpty ? nil : "\(selectedEpisodes.count) show\(selectedEpisodes.count == 1 ? "" : "s")",
                selectedMovies.isEmpty ? nil : "\(selectedMovies.count) movie\(selectedMovies.count == 1 ? "" : "s")",
                selectedGames.isEmpty ? nil : "\(selectedGames.count) game\(selectedGames.count == 1 ? "" : "s")",
                selectedAnimeEpisodes.isEmpty ? nil : "\(selectedAnimeEpisodes.count) anime"
            ].compactMap { $0 }
            if !parts.isEmpty {
                Text("· " + parts.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var headerLabel: String {
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        return selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

}

// MARK: - Month Grid

struct MonthGridView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    let episodesByDate: [Date: [Episode]]
    var moviesByDate: [Date: [Movie]] = [:]
    var gamesByDate: [Date: [SportGame]] = [:]
    var animeByDate: [Date: [AnimeEpisode]] = [:]
    let today: Date
    var maxMonth: Date = .distantFuture
    var onMonthChanged: ((Date) -> Void)? = nil
    var onGoToToday: (() -> Void)? = nil

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    private var canGoBack: Bool {
        displayedMonth > cal.startOfMonth(for: today)
    }

    private var canGoForward: Bool {
        displayedMonth < cal.startOfMonth(for: maxMonth)
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    // 42 cells (6 rows × 7 cols): nil = empty padding cell, Date = real day
    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: displayedMonth),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }

        // weekday index Mon=0 ... Sun=6
        let firstWeekday = (cal.component(.weekday, from: firstDay) + 5) % 7
        var result: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in range {
            result.append(cal.date(byAdding: .day, value: day - 1, to: firstDay))
        }
        // pad to complete grid
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            // Month navigation
            HStack {
                Button {
                    let newMonth = cal.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = newMonth }
                    onMonthChanged?(newMonth)
                } label: {
                    Image(systemName: "chevron.left")
                        .imageScale(.small)
                        .foregroundStyle(canGoBack ? .primary : .tertiary)
                }
                .disabled(!canGoBack)

                Spacer()
                Text(monthTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if !cal.isDate(selectedDate, inSameDayAs: today) || displayedMonth != cal.startOfMonth(for: today) {
                    Button("Today") { onGoToToday?() }
                        .font(.caption)
                        .fontWeight(.medium)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .transition(.opacity.combined(with: .scale))
                }
                Spacer()

                Button {
                    let newMonth = cal.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = newMonth }
                    onMonthChanged?(newMonth)
                } label: {
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(canGoForward ? .primary : .tertiary)
                }
                .disabled(!canGoForward)
            }
            .padding(.vertical, 4)

            // Weekday header row
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }
            }

            // Dot legend
            HStack(spacing: 12) {
                ForEach([(Color.accentColor, "Shows"), (DS.Color.movieTheaterRed, "Movies"), (Color.green, "Games"), (Color.purple, "Anime")], id: \.1) { color, label in
                    HStack(spacing: 4) {
                        Circle().fill(color).frame(width: 5, height: 5)
                        Text(label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.bottom, 4)

            // Day cells
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DayCell(
                            date: date,
                            isToday: cal.isDateInToday(date),
                            isSelected: cal.isDate(date, inSameDayAs: selectedDate),
                            isPast: date < today,
                            episodes: episodesByDate[date] ?? [],
                            movies: moviesByDate[date] ?? [],
                            games: gamesByDate[date] ?? [],
                            anime: animeByDate[date] ?? []
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedDate = date
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let isPast: Bool
    let episodes: [Episode]
    var movies: [Movie] = []
    var games: [SportGame] = []
    var anime: [AnimeEpisode] = []

    private var dayNumberColor: Color {
        if isSelected { return isToday ? .white : .primary }
        if isPast { return Color(.tertiaryLabel) }
        return .primary
    }

    /// Up to 4 dots, one per content type present, colored by type.
    private var dotColors: [Color] {
        var colors: [Color] = []
        if !episodes.isEmpty { colors.append(isToday ? .orange : .accentColor) }
        if !movies.isEmpty { colors.append(DS.Color.movieTheaterRed) }
        if !games.isEmpty { colors.append(.green) }
        if !anime.isEmpty { colors.append(.purple) }
        return Array(colors.prefix(4))
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(isToday ? Color.accentColor : Color(.systemGray4))
                        .frame(width: 30, height: 30)
                } else if isToday {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 30, height: 30)
                }

                Text(date.formatted(.dateTime.day()))
                    .font(.callout)
                    .fontWeight(isToday || isSelected ? .semibold : .regular)
                    .foregroundColor(dayNumberColor)
            }
            .frame(width: 30, height: 30)

            // Multi-dot episode indicator
            HStack(spacing: 2) {
                ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Calendar Episode Row

struct CalendarEpisodeRow: View {
    @Bindable var episode: Episode

    private var show: Show? { episode.show }
    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { cal.isDateInToday(episode.airDate) }

    private var posterURL: URL? {
        guard let s = show?.posterURL else { return nil }
        return URL(string: s)
    }

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: "tv").foregroundStyle(.tertiary)
                        }
                @unknown default:
                    Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(show?.title ?? "Unknown Show")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if let show { PlatformBadges(show: show) }
                }
                Text(episode.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isToday {
                    Label("New today", systemImage: "star.fill")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.orange)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").imageScale(.small).foregroundStyle(.tertiary)
                        Text(episode.airDate, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 14)
        }
        .contextMenu {
            if let show { EpisodeContextMenuItems(episode: episode, show: show) }
        }
    }
}

// MARK: - Calendar Movie Row

struct CalendarMovieRow: View {
    let movie: Movie

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: movie.posterImageURL.flatMap {
                URL(string: $0.absoluteString.replacingOccurrences(of: "/w300", with: "/w92"))
            }) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay { Image(systemName: "film").foregroundStyle(.tertiary) }
                @unknown default:
                    Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: 5) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(1)
                if let overview = movie.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if movie.releaseStatus == .streaming {
                    Label("Streaming now", systemImage: "play.circle.fill")
                        .font(.caption).foregroundStyle(.blue)
                } else {
                    Label("In theaters", systemImage: "film.fill")
                        .font(.caption).foregroundStyle(DS.Color.movieTheaterRed)
                }
            }
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Calendar Game Row

struct CalendarGameRow: View {
    let game: SportGame

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: game.team?.badgeImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay { Image(systemName: "sportscourt").foregroundStyle(.tertiary).imageScale(.small) }
                @unknown default:
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: 4) {
                Text(game.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "calendar").imageScale(.small).foregroundStyle(.tertiary)
                    Text(game.gameDate, style: .date).font(.caption).foregroundStyle(.secondary)
                    Text("·").font(.caption).foregroundStyle(.tertiary)
                    Text(game.formattedGameTime).font(.caption).foregroundStyle(.secondary)
                }
                if let league = game.team?.league {
                    Text(league).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 12)

            Spacer()
        }
    }
}

// MARK: - Calendar Anime Row

struct CalendarAnimeRow: View {
    let episode: AnimeEpisode

    private var show: AnimeShow? { episode.show }
    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { cal.isDateInToday(episode.airDate) }

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: show?.posterImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay { Image(systemName: "sparkles.tv").foregroundStyle(.tertiary) }
                @unknown default:
                    Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: 5) {
                Text(show?.displayTitle ?? "Unknown")
                    .font(.headline)
                    .lineLimit(1)
                Text(episode.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if isToday {
                    Label("New today", systemImage: "sparkles")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.purple)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").imageScale(.small).foregroundStyle(.tertiary)
                        Text(episode.airDate, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Calendar helpers

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
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

    for i in 0..<14 {
        let showIdx = i % 3
        let show = showIdx == 0 ? show1 : showIdx == 1 ? show2 : show3
        let ep = Episode(
            seasonNumber: 2,
            episodeNumber: i + 1,
            title: "Episode \(i + 1)",
            airDate: Calendar.current.date(byAdding: .day, value: i * 3, to: .now)!
        )
        ep.show = show
        ctx.insert(ep)
    }
    return container
}()
