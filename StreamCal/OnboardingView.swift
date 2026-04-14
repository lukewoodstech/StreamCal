import SwiftUI
import SwiftData

// MARK: - Onboarding Root

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("preferredPlatforms") private var preferredPlatformsRaw: String = ""
    @Environment(\.modelContext) private var modelContext

    @State private var currentPage = 0

    // Platform picker
    @State private var selectedPlatforms: Set<StreamingPlatform> = []

    // Content picker
    @State private var selectedShowIDs: Set<Int> = []
    @State private var selectedMovieIDs: Set<Int> = []
    @State private var selectedTeamItems: Set<SeedTeamItem> = []
    @State private var trendingShows: [TMDBShow] = []
    @State private var upcomingMovies: [TMDBMovie] = []
    @State private var isLoadingContent = false

    @State private var isImporting = false

    private var totalPages: Int { 1 + OnboardingFeature.allCases.count + 2 }
    private var platformPageIndex: Int { 1 + OnboardingFeature.allCases.count }
    private var tastePageIndex: Int { platformPageIndex + 1 }
    private var isLastPage: Bool { currentPage == totalPages - 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                splashPage.tag(0)
                ForEach(Array(OnboardingFeature.allCases.enumerated()), id: \.offset) { index, feature in
                    featureMockupPage(feature).tag(index + 1)
                }
                platformPickerPage.tag(platformPageIndex)
                tastePickerPage.tag(tastePageIndex)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            bottomControls
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? Color.accentColor : Color(.systemGray4))
                        .frame(width: i == currentPage ? 20 : 8, height: 8)
                        .animation(.spring(duration: 0.3), value: currentPage)
                }
            }

            Button {
                if isLastPage { finish() }
                else { withAnimation { currentPage += 1 } }
            } label: {
                Group {
                    if isImporting {
                        ProgressView().tint(.white)
                    } else {
                        Text(isLastPage ? "Get Started" : "Continue")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
            .disabled(isImporting)
            .padding(.horizontal, 32)

            if !isLastPage {
                Button("Skip") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .padding(.bottom, 48)
        .padding(.top, 16)
    }

    // MARK: - Splash

    private var splashPage: some View {
        VStack(spacing: 0) {
            Spacer()
            BrandMark(size: 90, showBackground: true)
                .padding(.bottom, 36)
            VStack(spacing: 12) {
                Text("StreamCal")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("Your personal streaming calendar")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
    }

    // MARK: - Feature Mockup Pages

    private func featureMockupPage(_ feature: OnboardingFeature) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Text(feature.title)
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(feature.description)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            MockupPhoneFrame {
                switch feature {
                case .calendar:      CalendarMockupView()
                case .nextUp:        NextUpMockupView()
                case .ai:            AIMockupView()
                case .notifications: NotificationMockupView()
                }
            }

            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Platform Picker

    private let primaryPlatforms: [StreamingPlatform] = [
        .netflix, .hulu, .disneyPlus, .max, .appleTV,
        .amazonPrime, .peacock, .paramountPlus, .espnPlus, .crunchyroll
    ]
    private let morePlatforms: [StreamingPlatform] = [
        .starz, .mgmPlus, .amcPlus, .fx, .discoveryPlus,
        .britbox, .shudder, .fubo, .tubi, .plutoTV,
        .nbc, .abc, .cbs, .fox, .pbs
    ]

    private var platformPickerPage: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Where do you watch?")
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text("Select your streaming services so StreamCal can personalize your recommendations.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    platformSection("Popular", platforms: primaryPlatforms)
                    platformSection("More Services", platforms: morePlatforms)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private func platformSection(_ title: String, platforms: [StreamingPlatform]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(platforms) { platform in
                    StreamingPlatformCard(
                        platform: platform,
                        isSelected: selectedPlatforms.contains(platform)
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if selectedPlatforms.contains(platform) { selectedPlatforms.remove(platform) }
                        else { selectedPlatforms.insert(platform) }
                    }
                }
            }
        }
    }

    // MARK: - Taste Picker

    private static let hardcodedTeams: [SeedTeamItem] = [
        SeedTeamItem(id: "13", displayName: "Los Angeles Lakers", league: "NBA", sport: "basketball", leaguePath: "nba",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nba/500/lal.png")),
        SeedTeamItem(id: "2",  displayName: "Boston Celtics",     league: "NBA", sport: "basketball", leaguePath: "nba",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nba/500/bos.png")),
        SeedTeamItem(id: "9",  displayName: "Golden State Warriors", league: "NBA", sport: "basketball", leaguePath: "nba",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nba/500/gs.png")),
        SeedTeamItem(id: "20", displayName: "Miami Heat",         league: "NBA", sport: "basketball", leaguePath: "nba",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nba/500/mia.png")),
        SeedTeamItem(id: "6",  displayName: "Dallas Cowboys",     league: "NFL", sport: "football",   leaguePath: "nfl",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500/dal.png")),
        SeedTeamItem(id: "27", displayName: "Kansas City Chiefs", league: "NFL", sport: "football",   leaguePath: "nfl",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500/kc.png")),
        SeedTeamItem(id: "25", displayName: "San Francisco 49ers", league: "NFL", sport: "football",  leaguePath: "nfl",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500/sf.png")),
        SeedTeamItem(id: "21", displayName: "Philadelphia Eagles", league: "NFL", sport: "football",  leaguePath: "nfl",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500/phi.png")),
        SeedTeamItem(id: "10", displayName: "New York Yankees",   league: "MLB", sport: "baseball",   leaguePath: "mlb",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/mlb/500/nyy.png")),
        SeedTeamItem(id: "19", displayName: "Los Angeles Dodgers", league: "MLB", sport: "baseball",  leaguePath: "mlb",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/mlb/500/lad.png")),
        SeedTeamItem(id: "1",  displayName: "Boston Bruins",      league: "NHL", sport: "hockey",     leaguePath: "nhl",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nhl/500/bos.png")),
        SeedTeamItem(id: "21", displayName: "Vegas Golden Knights", league: "NHL", sport: "hockey",   leaguePath: "nhl",
                     logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nhl/500/vgk.png")),
    ]

    private var tastePickerPage: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("What do you watch?")
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text("Pick favorites to seed your library with full schedules.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Selection count pills
                let totalCount = selectedShowIDs.count + selectedMovieIDs.count + selectedTeamItems.count
                if totalCount > 0 {
                    HStack(spacing: 8) {
                        if !selectedShowIDs.isEmpty {
                            selectionCountPill("\(selectedShowIDs.count) shows", color: DS.Color.shows)
                        }
                        if !selectedMovieIDs.isEmpty {
                            selectionCountPill("\(selectedMovieIDs.count) movies", color: DS.Color.movies)
                        }
                        if !selectedTeamItems.isEmpty {
                            selectionCountPill("\(selectedTeamItems.count) teams", color: DS.Color.sports)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // TV Shows
                    tasteSectionHeader("TV Shows", color: DS.Color.shows, symbol: "tv")
                    if isLoadingContent && trendingShows.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(trendingShows.prefix(12)) { show in
                                ContentSeedCard(
                                    posterURL: show.posterURL,
                                    title: show.name,
                                    subtitle: nil,
                                    placeholderSymbol: "tv",
                                    accentColor: DS.Color.shows,
                                    isSelected: selectedShowIDs.contains(show.id),
                                    isSquare: false
                                ) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    if selectedShowIDs.contains(show.id) { selectedShowIDs.remove(show.id) }
                                    else { selectedShowIDs.insert(show.id) }
                                }
                            }
                        }
                    }

                    // Movies
                    tasteSectionHeader("Movies", color: DS.Color.movies, symbol: "film")
                    if isLoadingContent && upcomingMovies.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(upcomingMovies.prefix(12)) { movie in
                                ContentSeedCard(
                                    posterURL: movie.posterURL,
                                    title: movie.title,
                                    subtitle: nil,
                                    placeholderSymbol: "film",
                                    accentColor: DS.Color.movies,
                                    isSelected: selectedMovieIDs.contains(movie.id),
                                    isSquare: false
                                ) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    if selectedMovieIDs.contains(movie.id) { selectedMovieIDs.remove(movie.id) }
                                    else { selectedMovieIDs.insert(movie.id) }
                                }
                            }
                        }
                    }

                    // Sports Teams
                    tasteSectionHeader("Sports Teams", color: DS.Color.sports, symbol: "sportscourt.fill")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Self.hardcodedTeams) { team in
                            ContentSeedCard(
                                posterURL: team.logoURL,
                                title: team.displayName,
                                subtitle: team.league,
                                placeholderSymbol: "sportscourt.fill",
                                accentColor: DS.Color.sports,
                                isSelected: selectedTeamItems.contains(team),
                                isSquare: true
                            ) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if selectedTeamItems.contains(team) { selectedTeamItems.remove(team) }
                                else { selectedTeamItems.insert(team) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .task {
            guard trendingShows.isEmpty && upcomingMovies.isEmpty else { return }
            isLoadingContent = true
            async let shows = TMDBService.shared.fetchTrendingShows()
            async let movies = TMDBService.shared.fetchUpcomingMovies()
            trendingShows = (try? await shows) ?? []
            upcomingMovies = (try? await movies) ?? []
            isLoadingContent = false
        }
    }

    private func tasteSectionHeader(_ title: String, color: Color, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
        }
    }

    private func selectionCountPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Finish

    private func finish() {
        preferredPlatformsRaw = selectedPlatforms.map(\.rawValue).joined(separator: ",")
        let hasSelections = !selectedShowIDs.isEmpty || !selectedMovieIDs.isEmpty || !selectedTeamItems.isEmpty
        guard hasSelections else { hasCompletedOnboarding = true; return }

        isImporting = true
        let showMap = Dictionary(uniqueKeysWithValues: trendingShows.map { ($0.id, $0) })
        let movieMap = Dictionary(uniqueKeysWithValues: upcomingMovies.map { ($0.id, $0) })
        let context = modelContext
        let showIDsToImport = Array(selectedShowIDs)
        let movieIDsToImport = Array(selectedMovieIDs)
        let teamsToImport = Array(selectedTeamItems)

        Task {
            await withTaskGroup(of: Void.self) { group in
                for id in showIDsToImport {
                    if let show = showMap[id] {
                        group.addTask { await Self.importSeedShow(tmdbShow: show, context: context) }
                    }
                }
                for id in movieIDsToImport {
                    if let movie = movieMap[id] {
                        group.addTask { await Self.importSeedMovie(tmdbMovie: movie, context: context) }
                    }
                }
                for team in teamsToImport {
                    group.addTask { await Self.importSeedTeam(team: team, context: context) }
                }
            }
            hasCompletedOnboarding = true
        }
    }

    // MARK: - Seed Imports

    private static func importSeedShow(tmdbShow: TMDBShow, context: ModelContext) async {
        do {
            let existing = try? context.fetch(FetchDescriptor<Show>())
            if existing?.contains(where: { $0.tmdbID == tmdbShow.id }) == true { return }

            let details = try await TMDBService.shared.fetchShowDetails(tmdbID: tmdbShow.id)
            let show = Show(
                title: tmdbShow.name,
                platform: StreamingPlatform.other.rawValue,
                tmdbID: tmdbShow.id,
                posterURL: tmdbShow.posterURL?.absoluteString,
                showStatus: details.status
            )
            context.insert(show)

            async let providersFetch = TMDBService.shared.fetchWatchProviders(tmdbID: tmdbShow.id, mediaType: "tv")
            let allEpisodes = try await TMDBService.shared.fetchAllEpisodes(tmdbID: tmdbShow.id)
            show.watchProviderNames = (try? await providersFetch)?.map(\.providerName) ?? []

            for ep in allEpisodes {
                let episode = Episode(
                    seasonNumber: ep.seasonNumber,
                    episodeNumber: ep.episodeNumber,
                    title: ep.name ?? "",
                    airDate: ep.parsedAirDate ?? .distantFuture,
                    isWatched: false
                )
                episode.show = show
                context.insert(episode)
            }
            try? context.save()
        } catch { /* silent */ }
    }

    private static func importSeedMovie(tmdbMovie: TMDBMovie, context: ModelContext) async {
        do {
            let existing = try? context.fetch(FetchDescriptor<Movie>())
            if existing?.contains(where: { $0.tmdbID == tmdbMovie.id }) == true { return }

            let details = try await TMDBService.shared.fetchMovieDetails(tmdbID: tmdbMovie.id)
            let movie = Movie(
                title: details.title,
                tmdbID: details.id,
                posterURL: details.posterURL?.absoluteString,
                overview: details.overview,
                tagline: details.tagline,
                genres: details.genres?.map(\.name) ?? [],
                theatricalReleaseDate: details.usTheatricalDate() ?? .distantFuture,
                streamingReleaseDate: details.usStreamingDate(),
                tmdbStatus: details.status
            )
            let providers = (try? await TMDBService.shared.fetchWatchProviders(tmdbID: details.id, mediaType: "movie")) ?? []
            movie.watchProviderNames = providers.map(\.providerName)
            context.insert(movie)
            try? context.save()
        } catch { /* silent */ }
    }

    private static func importSeedTeam(team: SeedTeamItem, context: ModelContext) async {
        do {
            let existing = try? context.fetch(FetchDescriptor<SportTeam>())
            if existing?.contains(where: { $0.sportsDBID == team.id && $0.league == team.league }) == true { return }

            let sportTeam = SportTeam(
                name: team.displayName,
                sportsDBID: team.id,
                sport: team.sport,
                league: team.league,
                leagueID: team.leaguePath,
                country: "USA",
                badgeURL: team.logoURL?.absoluteString,
                dataSource: "espn"
            )
            context.insert(sportTeam)
            try? context.save()

            let events = try await ESPNService.shared.fetchSchedule(
                espnTeamID: team.id,
                sport: team.sport,
                leaguePath: team.leaguePath
            )

            for event in events {
                let comp = event.competitions.first
                let home = comp?.competitors.first(where: { $0.homeAway == "home" })?.team.displayName ?? ""
                let away = comp?.competitors.first(where: { $0.homeAway == "away" })?.team.displayName ?? ""
                let isCompleted = comp?.status?.type?.completed ?? false
                var result: String? = nil
                if isCompleted,
                   let homeScore = comp?.competitors.first(where: { $0.homeAway == "home" })?.score?.value,
                   let awayScore = comp?.competitors.first(where: { $0.homeAway == "away" })?.score?.value {
                    result = "\(Int(awayScore))–\(Int(homeScore))"
                }
                let game = SportGame(
                    sportsDBEventID: event.id,
                    title: event.name,
                    homeTeam: home,
                    awayTeam: away,
                    gameDate: event.parsedDate ?? .distantFuture,
                    venue: comp?.venue?.fullName,
                    result: result,
                    isCompleted: isCompleted
                )
                game.team = sportTeam
                context.insert(game)
            }
            try? context.save()
            await NotificationService.shared.scheduleNotifications(for: sportTeam)
        } catch { /* silent */ }
    }
}

// MARK: - Seed Team Item

struct SeedTeamItem: Identifiable, Hashable {
    let id: String
    let displayName: String
    let league: String
    let sport: String
    let leaguePath: String
    let logoURL: URL?

    static func == (lhs: SeedTeamItem, rhs: SeedTeamItem) -> Bool {
        lhs.id == rhs.id && lhs.league == rhs.league
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(league)
    }
}

// MARK: - Onboarding Feature Enum

private enum OnboardingFeature: Int, CaseIterable {
    case calendar, nextUp, ai, notifications

    var title: String {
        switch self {
        case .calendar:      return "A Calendar Built for Streaming"
        case .nextUp:        return "Everything That's Next Up"
        case .ai:            return "AI That Knows Your Library"
        case .notifications: return "Never Miss a Drop"
        }
    }
    var description: String {
        switch self {
        case .calendar:
            return "Browse any date to see episodes dropping, theatrical releases, and game days — all together."
        case .nextUp:
            return "TV episodes, upcoming movies, and sports games organized into one forward-looking feed."
        case .ai:
            return "Ask StreamCal anything — \"what should I watch tonight?\" — and get personalized answers from your actual library."
        case .notifications:
            return "Get reminded when new episodes air and when games tip off. Customize your reminder times in Settings."
        }
    }
}

// MARK: - Mockup Phone Frame

private struct MockupPhoneFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(.systemGray5))
                .frame(width: 220, height: 380)
                .shadow(color: .black.opacity(0.13), radius: 18, x: 0, y: 8)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground))
                .frame(width: 204, height: 364)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
            content()
                .frame(width: 204, height: 364)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}

// MARK: - Calendar Mockup

private struct CalendarMockupView: View {
    private let dotDays: [(day: Int, color: Color)] = [
        (6, DS.Color.shows), (8, DS.Color.movies), (10, DS.Color.sports),
        (13, DS.Color.shows), (15, DS.Color.shows), (15, DS.Color.sports),
        (20, DS.Color.movies), (22, DS.Color.shows), (27, DS.Color.sports)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            HStack {
                Text("April 2026").font(.system(size: 10, weight: .bold))
                Spacer()
                Image(systemName: "chevron.left").font(.system(size: 9))
                    .padding(.trailing, 6)
                Image(systemName: "chevron.right").font(.system(size: 9))
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)

            // Weekday labels
            HStack(spacing: 0) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                    Text(d).font(.system(size: 8)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 2)

            // Day grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
                // April 2026 starts on Wednesday — 3 empty cells
                ForEach(0..<3) { _ in Color.clear.frame(height: 22) }
                ForEach(1...30, id: \.self) { day in
                    let isToday = day == 6
                    let dayDots = dotDays.filter { $0.day == day }.map { $0.color }
                    VStack(spacing: 1) {
                        Text("\(day)")
                            .font(.system(size: 8, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? .white : .primary)
                            .frame(width: 16, height: 16)
                            .background(isToday ? Color.accentColor : Color.clear, in: Circle())
                        HStack(spacing: 1) {
                            ForEach(dayDots.prefix(3), id: \.self) { color in
                                Circle().fill(color).frame(width: 3, height: 3)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(height: 26)
                }
            }
            .padding(.horizontal, 8)

            Divider().padding(.vertical, 6)

            // Day detail
            VStack(alignment: .leading, spacing: 0) {
                Text("Wednesday, Apr 6")
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 5)
                mockCalRow("Severance", detail: "S2E10 · Apple TV+", color: DS.Color.shows)
                mockCalRow("The Last of Us", detail: "S2E2 · Max", color: DS.Color.shows)
                mockCalRow("Lakers vs Celtics", detail: "7:30 PM · NBA", color: DS.Color.sports)
            }

            Spacer()
        }
        .background(Color(.systemBackground))
    }

    private func mockCalRow(_ title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 2.5, height: 28)
            RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.15)).frame(width: 18, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 8, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 7)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 2)
    }
}

// MARK: - Next Up Mockup

private struct NextUpMockupView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker
            HStack(spacing: 0) {
                ForEach(["Shows", "Movies", "Sports"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 8, weight: label == "Shows" ? .semibold : .regular))
                        .foregroundStyle(label == "Shows" ? .primary : .secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(label == "Shows" ? Color(.systemBackground) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(3)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12).padding(.top, 10)

            sectionHeader("Airing Today")
            mockEpisodeCard(title: "Severance", episode: "S2E10", badge: "Today", color: DS.Color.shows)
                .padding(.horizontal, 12)
            mockEpisodeCard(title: "The Last of Us", episode: "S2E2", badge: "Today", color: DS.Color.shows)
                .padding(.horizontal, 12)

            sectionHeader("This Week")
            mockEpisodeCard(title: "The Bear", episode: "S3E1", badge: "Thu", color: DS.Color.shows)
                .padding(.horizontal, 12)
            mockEpisodeCard(title: "Thunderbolts", episode: "In Theaters", badge: "Fri", color: DS.Color.movies)
                .padding(.horizontal, 12)

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 3)
    }

    private func mockEpisodeCard(title: String, episode: String, badge: String, color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.2))
                .frame(width: 26, height: 38)
                .overlay(Image(systemName: "tv").font(.system(size: 10)).foregroundStyle(color))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                Text(episode).font(.system(size: 8)).foregroundStyle(.secondary)
                Text(badge)
                    .font(.system(size: 7, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(color.opacity(0.15)).foregroundStyle(color)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(7)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 4)
    }
}

// MARK: - AI Mockup

private struct AIMockupView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            HStack {
                Image(systemName: "chevron.left").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("Ask StreamCal").font(.system(size: 10, weight: .semibold))
                Spacer()
                Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(.indigo)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // User bubble
                    HStack {
                        Spacer(minLength: 30)
                        Text("What action movie\nshould I watch tonight?")
                            .font(.system(size: 9))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Assistant bubble
                    HStack(alignment: .top, spacing: 5) {
                        ZStack {
                            Circle().fill(Color.indigo.opacity(0.15)).frame(width: 18, height: 18)
                            Image(systemName: "sparkles").font(.system(size: 8)).foregroundStyle(.indigo)
                        }
                        Text("Try **Mission: Impossible** — it's exactly your vibe and streaming on Paramount+!")
                            .font(.system(size: 9))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .frame(maxWidth: 130, alignment: .leading)
                        Spacer(minLength: 10)
                    }

                    // Second user message
                    HStack {
                        Spacer(minLength: 30)
                        Text("Any Tom Hanks\nrecommendations?")
                            .font(.system(size: 9))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 10).padding(.top, 8)
            }

            Divider()
            // Mock input bar
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 24)
                    .overlay(
                        Text("Ask anything…")
                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                            .padding(.leading, 8),
                        alignment: .leading
                    )
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18)).foregroundStyle(Color(.systemGray3))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Notification Mockup

private struct NotificationMockupView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                Text("9:41").font(.system(size: 11, weight: .semibold))
                Spacer()
                Image(systemName: "wifi").font(.system(size: 9))
                Image(systemName: "battery.100").font(.system(size: 9))
            }
            .padding(.horizontal, 16).padding(.top, 10)

            // Lock icon
            Image(systemName: "lock.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            // Notification banners
            VStack(spacing: 8) {
                mockBanner(icon: "calendar", iconColor: DS.Color.shows,
                           title: "Severance airs today",
                           body: "S2E10 drops on Apple TV+ at midnight")
                mockBanner(icon: "sportscourt.fill", iconColor: DS.Color.sports,
                           title: "Lakers tip off in 2 hours",
                           body: "Los Angeles Lakers vs Boston Celtics")
                mockBanner(icon: "film.fill", iconColor: DS.Color.movies,
                           title: "Thunderbolts is now in theaters",
                           body: "Check showtimes near you")
            }
            .padding(.horizontal, 12).padding(.top, 16)

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func mockBanner(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(iconColor.opacity(0.15)).frame(width: 26, height: 26)
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("StreamCal").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("now").font(.system(size: 7)).foregroundStyle(.tertiary)
                }
                Text(title).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                Text(body).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Streaming Platform Card

private struct StreamingPlatformCard: View {
    let platform: StreamingPlatform
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [platform.cardBackgroundColor.opacity(0.8), platform.cardBackgroundColor],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 80)
                    .overlay(
                        VStack(spacing: 5) {
                            Image(systemName: platform.sfSymbol)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                            Text(platform.abbreviatedName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2.5)
                    )

                // Checkmark badge
                if isSelected {
                    ZStack {
                        Circle().fill(.white).frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(platform.cardBackgroundColor)
                    }
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isSelected ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Content Seed Card

private struct ContentSeedCard: View {
    let posterURL: URL?
    let title: String
    let subtitle: String?
    let placeholderSymbol: String
    let accentColor: Color
    let isSelected: Bool
    let isSquare: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Poster
                CachedAsyncImage(url: posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay(
                                Image(systemName: placeholderSymbol)
                                    .foregroundStyle(.tertiary)
                                    .font(.title3)
                            )
                    }
                }
                .aspectRatio(isSquare ? 1 : 2.0/3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                )
                // Title band
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                if let sub = subtitle {
                                    Text(sub)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                            }
                            .padding(.horizontal, 7).padding(.bottom, 7)
                        }
                }

                // Checkmark badge
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                        .background(Circle().fill(.white).padding(3))
                        .padding(5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isSelected ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: [Show.self, Episode.self, Movie.self, SportTeam.self, SportGame.self], inMemory: true)
}
