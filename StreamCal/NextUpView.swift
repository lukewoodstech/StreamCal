import SwiftUI
import SwiftData

struct NextUpView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var contentType: LibraryContentType = .shows

    @Query(sort: \Show.title)
    private var shows: [Show]

    @Query(sort: \Movie.theatricalReleaseDate)
    private var movies: [Movie]

    @Query(sort: \SportGame.gameDate)
    private var games: [SportGame]

    @Query(sort: \AnimeShow.titleRomaji)
    private var animeShows: [AnimeShow]

    @Query(sort: \SportTeam.name)
    private var teams: [SportTeam]

    @EnvironmentObject private var purchaseService: PurchaseService

    @State private var aiSuggestion: String? = nil
    @State private var isLoadingAI = false
    @State private var showingAISheet = false
    @State private var showingPaywall = false
    @State private var showingAskStreamCal = false

    private var activeShows: [Show] { shows.filter { !$0.isArchived } }

    // MARK: - TV sections

    private var airingToday: [(show: Show, episode: Episode)] { WatchPlanner.nextUpAiringToday(from: shows) }
    private var thisWeek: [(show: Show, episode: Episode)] { WatchPlanner.nextUpThisWeek(from: shows) }
    private var comingSoon: [(show: Show, episode: Episode)] { WatchPlanner.nextUpComingSoon(from: shows) }
    private var dateTBA: [(show: Show, episode: Episode)] { WatchPlanner.nextUpDateTBA(from: shows) }

    // MARK: - Movie sections

    private var moviesInTheaters: [Movie] {
        movies.filter { !$0.isArchived && $0.releaseStatus == .released }
    }

    private var moviesComingSoon: [Movie] {
        movies.filter { !$0.isArchived && $0.releaseStatus == .comingSoon && $0.theatricalReleaseDate != .distantFuture }
    }

    private var moviesStreamingSoon: [Movie] {
        movies.filter { !$0.isArchived && $0.releaseStatus == .streaming }
            .sorted { ($0.streamingReleaseDate ?? .distantFuture) < ($1.streamingReleaseDate ?? .distantFuture) }
    }

    // MARK: - Game sections

    private var gamesToday: [SportGame] {
        games.filter { !$0.isCompleted && Calendar.current.isDateInToday($0.gameDate) }
    }

    private var gamesThisWeek: [SportGame] {
        let cal = Calendar.current
        let now = Date.now
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now))!
        return games.filter {
            !$0.isCompleted &&
            $0.gameDate > now &&
            !cal.isDateInToday($0.gameDate) &&
            $0.gameDate <= weekEnd &&
            $0.gameDate != .distantFuture
        }
    }

    private var gamesUpcoming: [SportGame] {
        let cal = Calendar.current
        let now = Date.now
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now))!
        return Array(games.filter {
            !$0.isCompleted && $0.gameDate > weekEnd && $0.gameDate != .distantFuture
        }.prefix(20))
    }

    // MARK: - Anime sections

    private var animeAiringToday: [(show: AnimeShow, episode: AnimeEpisode)] {
        animeShows.filter { !$0.isArchived }.compactMap { show -> (AnimeShow, AnimeEpisode)? in
            let ep = show.episodes.filter { Calendar.current.isDateInToday($0.airDate) }
                .sorted { $0.episodeNumber < $1.episodeNumber }.first
            guard let ep else { return nil }
            return (show, ep)
        }.sorted { $0.show.displayTitle < $1.show.displayTitle }
    }

    private var animeThisWeek: [(show: AnimeShow, episode: AnimeEpisode)] {
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: .now)) ?? .now
        return animeShows.filter { !$0.isArchived }.flatMap { show in
            show.episodes.filter {
                $0.airDate != .distantFuture &&
                $0.airDate >= tomorrow && $0.airDate < weekEnd
            }.map { (show: show, episode: $0) }
        }.sorted { lhs, rhs in
            if lhs.episode.airDate != rhs.episode.airDate { return lhs.episode.airDate < rhs.episode.airDate }
            return lhs.show.displayTitle < rhs.show.displayTitle
        }
    }

    private var animeComingSoon: [(show: AnimeShow, episode: AnimeEpisode)] {
        let cal = Calendar.current
        let beyond = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: .now)) ?? .now
        return animeShows.filter { !$0.isArchived }.flatMap { show in
            show.episodes.filter {
                $0.airDate != .distantFuture && $0.airDate >= beyond
            }.map { (show: show, episode: $0) }
        }.sorted { lhs, rhs in
            if lhs.episode.airDate != rhs.episode.airDate { return lhs.episode.airDate < rhs.episode.airDate }
            return lhs.show.displayTitle < rhs.show.displayTitle
        }
    }

    private var hasUpcomingContent: Bool {
        switch contentType {
        case .shows:  return !airingToday.isEmpty || !thisWeek.isEmpty || !comingSoon.isEmpty || !dateTBA.isEmpty || !animeAiringToday.isEmpty || !animeThisWeek.isEmpty || !animeComingSoon.isEmpty
        case .movies: return !moviesInTheaters.isEmpty || !moviesComingSoon.isEmpty || !moviesStreamingSoon.isEmpty
        case .sports: return !gamesToday.isEmpty || !gamesThisWeek.isEmpty || !gamesUpcoming.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasUpcomingContent {
                    noUpcomingView
                } else {
                    list
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text("Next Up")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    Picker("Content Type", selection: $contentType) {
                        ForEach(LibraryContentType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    Divider()
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAskStreamCal = true } label: {
                        Image(systemName: "sparkles")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(DS.Color.ai)
                    }
                }
            }
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .sheet(isPresented: $showingAISheet) { aiSheet }
            .sheet(isPresented: $showingPaywall) { AppPaywallView().environmentObject(purchaseService) }
            .sheet(isPresented: $showingAskStreamCal) {
                AskStreamCalView().environmentObject(purchaseService)
            }
        }
    }

    // MARK: - No Upcoming

    private var libraryIsEmpty: Bool {
        switch contentType {
        case .shows:  return shows.filter({ !$0.isArchived }).isEmpty && animeShows.filter({ !$0.isArchived }).isEmpty
        case .movies: return movies.filter({ !$0.isArchived }).isEmpty
        case .sports: return teams.isEmpty
        }
    }

    private var noUpcomingView: some View {
        Group {
            if libraryIsEmpty {
                switch contentType {
                case .shows:
                    ContentUnavailableView {
                        Label("Your Library is Empty", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("Add TV shows or anime to see upcoming episodes here.")
                    } actions: {
                        Text("Go to **Library** to get started")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .movies:
                    ContentUnavailableView {
                        Label("No Movies Added", systemImage: "film.stack")
                    } description: {
                        Text("Track upcoming releases, theatrical dates, and streaming debuts.")
                    } actions: {
                        Text("Go to **Library → Movies** to add your first movie")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .sports:
                    ContentUnavailableView {
                        Label("No Teams Followed", systemImage: "sportscourt.fill")
                    } description: {
                        Text("Follow your favorite teams to see their upcoming games.")
                    } actions: {
                        Text("Go to **Library → Sports** to follow a team")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                switch contentType {
                case .shows:
                    ContentUnavailableView("All Caught Up", systemImage: "checkmark.circle",
                        description: Text("No upcoming episodes in the next few weeks. Check back soon."))
                case .movies:
                    ContentUnavailableView("No Upcoming Releases", systemImage: "film",
                        description: Text("None of your tracked movies have upcoming release dates right now."))
                case .sports:
                    ContentUnavailableView("No Upcoming Games", systemImage: "sportscourt",
                        description: Text("No scheduled games in the near future. Pull to refresh."))
                }
            }
        }
        .refreshable { await refreshAll() }
    }

    // MARK: - Main list

    private var list: some View {
        List {
            switch contentType {
            case .shows:
                // AI "What to watch tonight" card
                Section {
                    Button {
                        if purchaseService.isPro {
                            showingAISheet = true
                            if aiSuggestion == nil { loadAISuggestion() }
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(DS.Color.ai)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("What should I watch tonight?")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if !purchaseService.isPro {
                                        Text("PRO")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text("Tap for a personalized suggestion")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .imageScale(.small)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                if !airingToday.isEmpty || !animeAiringToday.isEmpty {
                    Section {
                        ForEach(airingToday, id: \.episode.persistentModelID) { item in
                            EpisodeCard(show: item.show, episode: item.episode)
                        }
                        ForEach(animeAiringToday, id: \.episode.persistentModelID) { item in
                            AnimeEpisodeCard(show: item.show, episode: item.episode)
                        }
                    } header: {
                        NextUpSectionHeader(title: "Airing Today", icon: "star.fill", color: .orange)
                    }
                }
                if !thisWeek.isEmpty || !animeThisWeek.isEmpty {
                    Section {
                        ForEach(thisWeek, id: \.episode.persistentModelID) { item in
                            EpisodeCard(show: item.show, episode: item.episode)
                        }
                        ForEach(animeThisWeek, id: \.episode.persistentModelID) { item in
                            AnimeEpisodeCard(show: item.show, episode: item.episode)
                        }
                    } header: {
                        NextUpSectionHeader(title: "This Week", icon: "calendar", color: .blue)
                    }
                }
                if !comingSoon.isEmpty || !animeComingSoon.isEmpty {
                    Section {
                        ForEach(comingSoon, id: \.episode.persistentModelID) { item in
                            EpisodeCard(show: item.show, episode: item.episode)
                        }
                        ForEach(animeComingSoon, id: \.episode.persistentModelID) { item in
                            AnimeEpisodeCard(show: item.show, episode: item.episode)
                        }
                    } header: {
                        NextUpSectionHeader(title: "Coming Soon", icon: "clock", color: .secondary)
                    }
                }
                if !dateTBA.isEmpty {
                    Section {
                        ForEach(dateTBA, id: \.episode.persistentModelID) { item in
                            EpisodeCard(show: item.show, episode: item.episode)
                        }
                    } header: {
                        NextUpSectionHeader(title: "Date TBA", icon: "calendar.badge.clock", color: .secondary)
                    }
                }

            case .movies:
                if !moviesInTheaters.isEmpty {
                    Section {
                        ForEach(moviesInTheaters) { movie in
                            NavigationLink(destination: MovieDetailView(movie: movie)) {
                                MovieCard(movie: movie)
                            }
                        }
                    } header: {
                        NextUpSectionHeader(title: "In Theaters", icon: "film.fill", color: DS.Color.movieTheaterRed)
                    }
                }
                if !moviesComingSoon.isEmpty {
                    Section {
                        ForEach(moviesComingSoon) { movie in
                            NavigationLink(destination: MovieDetailView(movie: movie)) {
                                MovieCard(movie: movie)
                            }
                        }
                    } header: {
                        NextUpSectionHeader(title: "Coming to Theaters", icon: "ticket.fill", color: .secondary)
                    }
                }
                if !moviesStreamingSoon.isEmpty {
                    Section {
                        ForEach(moviesStreamingSoon) { movie in
                            NavigationLink(destination: MovieDetailView(movie: movie)) {
                                MovieCard(movie: movie)
                            }
                        }
                    } header: {
                        NextUpSectionHeader(title: "Now Streaming", icon: "play.circle.fill", color: .blue)
                    }
                }

            case .sports:
                if !gamesToday.isEmpty {
                    Section {
                        ForEach(gamesToday) { game in
                            NavigationLink(destination: TeamDetailView(team: game.team ?? SportTeam(name: "", sportsDBID: "", sport: "", league: ""))) {
                                UpcomingGameRow(game: game)
                            }
                        }
                    } header: {
                        NextUpSectionHeader(title: "Games Today", icon: "sportscourt.fill", color: .orange)
                    }
                }
                if !gamesThisWeek.isEmpty {
                    Section {
                        ForEach(gamesThisWeek) { game in
                            NavigationLink(destination: TeamDetailView(team: game.team ?? SportTeam(name: "", sportsDBID: "", sport: "", league: ""))) {
                                UpcomingGameRow(game: game)
                            }
                        }
                    } header: {
                        NextUpSectionHeader(title: "Games This Week", icon: "calendar", color: .blue)
                    }
                }
                if !gamesUpcoming.isEmpty {
                    Section {
                        ForEach(gamesUpcoming) { game in
                            NavigationLink(destination: TeamDetailView(team: game.team ?? SportTeam(name: "", sportsDBID: "", sport: "", league: ""))) {
                                UpcomingGameRow(game: game)
                            }
                        }
                    } header: {
                        NextUpSectionHeader(title: "Upcoming Games", icon: "clock", color: .secondary)
                    }
                }

            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await refreshAll() }
    }

    // MARK: - AI Sheet

    private var aiSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoadingAI {
                        ProgressView("Thinking...")
                            .padding(.top, 40)
                    } else if let suggestion = aiSuggestion {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(DS.Color.ai)
                                    Text("Tonight's Pick")
                                        .font(.headline)
                                }
                                Text(suggestion)
                                    .font(.body)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                            let matches = LibraryMatches.find(in: suggestion, shows: shows, movies: movies, teams: teams)
                            if !matches.isEmpty {
                                RecommendedItemsRow(matches: matches)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)

                        Button("Refresh Suggestion") { loadAISuggestion() }
                            .buttonStyle(.bordered)
                    } else {
                        ContentUnavailableView("Unable to Generate Suggestion",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Check your Claude API key in Settings."))
                    }
                }
            }
            .navigationTitle("What to Watch Tonight?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingAISheet = false }
                }
            }
        }
    }

    private func loadAISuggestion() {
        isLoadingAI = true
        aiSuggestion = nil
        Task {
            let backlog = shows.filter { !$0.isArchived }.compactMap { show -> (String, Int)? in
                let count = show.backlogEpisodes.count
                guard count > 0 else { return nil }
                return (show.title, count)
            }
            let upcoming = shows.filter { !$0.isArchived }.compactMap { show -> (String, Int)? in
                guard let ep = show.nextUpcomingEpisode, ep.airDate != .distantFuture else { return nil }
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                            to: Calendar.current.startOfDay(for: ep.airDate)).day ?? 0
                return (show.title, days)
            }
            let watchedCount = shows.flatMap { $0.episodes }.filter { $0.isWatched }.count
            let result = await ClaudeService.generateWatchRecommendation(
                backlog: backlog.map { (showTitle: $0.0, count: $0.1) },
                upcoming: upcoming.map { (showTitle: $0.0, daysUntil: $0.1) },
                watchedCount: watchedCount
            )
            aiSuggestion = result
            isLoadingAI = false
        }
    }

    // MARK: - Helpers

    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await RefreshService.shared.refreshAllShows(modelContext: modelContext) }
            group.addTask { await RefreshService.shared.refreshAllMovies(modelContext: modelContext) }
            group.addTask { await RefreshService.shared.refreshAllTeams(modelContext: modelContext) }
            group.addTask { await RefreshService.shared.refreshAllAnime(modelContext: modelContext) }
        }
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
        .padding(.top, 8)
        .padding(.bottom, 2)
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
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.tertiary)
                        }
                @unknown default:
                    Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 54, height: 81)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(show.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    PlatformBadges(show: show)
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
        if isToday {
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

// MARK: - Movie Card

struct MovieCard: View {
    let movie: Movie

    private var cal: Calendar { Calendar.current }

    private var releaseDate: Date? {
        switch movie.releaseStatus {
        case .comingSoon, .released: return movie.theatricalReleaseDate == .distantFuture ? nil : movie.theatricalReleaseDate
        case .streaming: return movie.streamingReleaseDate
        default: return nil
        }
    }

    private var daysUntil: Int? {
        guard let date = releaseDate, date > .now else { return nil }
        let today = cal.startOfDay(for: .now)
        let d = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: date)).day ?? 0
        return d > 0 ? d : nil
    }

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: movie.posterImageURL.flatMap {
                URL(string: $0.absoluteString.replacingOccurrences(of: "/w300", with: "/w92"))
            }) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: "film")
                                .foregroundStyle(.tertiary)
                        }
                @unknown default:
                    Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 54, height: 81)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

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

                HStack(spacing: 5) {
                    if let date = releaseDate {
                        Image(systemName: "calendar")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let days = daysUntil, days <= 14 {
                            Text("in \(days)d")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    } else if movie.releaseStatus == .released {
                        Label("In Theaters Now", systemImage: "film.fill")
                            .font(.caption)
                            .foregroundStyle(DS.Color.movieTheaterRed)
                    } else if movie.releaseStatus == .streaming {
                        Label("Streaming Now", systemImage: "play.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Upcoming Game Row

struct UpcomingGameRow: View {
    let game: SportGame

    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { game.gameDate != .distantFuture && cal.isDateInToday(game.gameDate) }

    private var daysUntil: Int? {
        guard game.gameDate != .distantFuture, game.gameDate > .now else { return nil }
        let today = cal.startOfDay(for: .now)
        let d = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: game.gameDate)).day ?? 0
        return d > 0 ? d : nil
    }

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: game.team?.badgeImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                default:
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: "sportscourt")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: 3) {
                Text(game.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if isToday {
                        Label("Today · \(game.formattedGameTime)", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if game.gameDate != .distantFuture {
                        Image(systemName: "calendar")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                        Text(game.gameDate, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(game.formattedGameTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let days = daysUntil, days <= 7 {
                            Text("in \(days)d")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    } else {
                        Text("TBA").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let league = game.team?.league {
                    Text(league)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Anime Episode Card

struct AnimeEpisodeCard: View {
    let show: AnimeShow
    @Bindable var episode: AnimeEpisode

    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { cal.isDateInToday(episode.airDate) }

    private var daysUntil: Int {
        let today = cal.startOfDay(for: .now)
        return cal.dateComponents([.day], from: today, to: cal.startOfDay(for: episode.airDate)).day ?? 0
    }

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: show.posterImageURL) { phase in
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
            .frame(width: 54, height: 81)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            VStack(alignment: .leading, spacing: 5) {
                Text(show.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(episode.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if isToday {
                    Label("New today", systemImage: "sparkles")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
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
                                .background(Color.purple)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Episode Context Menu Items (reusable)

struct EpisodeContextMenuItems: View {
    let episode: Episode
    let show: Show

    var body: some View {
        EmptyView()
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
    let container = try! ModelContainer(for: Show.self, Episode.self, Movie.self, SportTeam.self, SportGame.self, AnimeShow.self, AnimeEpisode.self, configurations: config)
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

    // Movie — coming soon
    let movie = Movie(title: "Mission: Impossible 8",
                      overview: "Ethan Hunt faces his most dangerous mission.",
                      theatricalReleaseDate: cal.date(byAdding: .day, value: 5, to: .now)!)
    ctx.insert(movie)

    // Sport team + game
    let team = SportTeam(name: "Los Angeles Lakers", sportsDBID: "134880",
                          sport: "Basketball", league: "NBA")
    ctx.insert(team)
    let game = SportGame(sportsDBEventID: "preview1", title: "LA Lakers vs Boston Celtics",
                          homeTeam: "Los Angeles Lakers", awayTeam: "Boston Celtics",
                          gameDate: cal.date(byAdding: .day, value: 2, to: .now)!)
    game.team = team
    ctx.insert(game)

    return container
}()
