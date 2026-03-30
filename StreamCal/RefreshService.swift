import Foundation
import SwiftData

/// Silently refreshes episode data from TMDB for all tracked shows on app launch.
/// Inserts new episodes and updates air dates on existing ones if TMDB has changed them.
@MainActor
final class RefreshService {

    static let shared = RefreshService()

    /// Call once on app launch (or on manual pull-to-refresh).
    /// Fetches fresh episodes for every tracked show, syncs any changes, then reschedules notifications.
    func refreshAllShows(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Show>()
        guard let shows = try? modelContext.fetch(descriptor) else { return }

        let trackedShows = shows.filter { $0.tmdbID != nil && !$0.isArchived }
        guard !trackedShows.isEmpty else { return }

        for show in trackedShows {
            try? await syncShow(show, modelContext: modelContext)
        }

        try? modelContext.save()
        await NotificationService.shared.scheduleNotifications(for: trackedShows)
    }

    /// Single-show refresh used by ShowDetailView for on-demand refresh.
    /// Throws on network/decode failure so the caller can surface the error.
    func refreshSingleShow(_ show: Show, modelContext: ModelContext) async throws {
        try await syncShow(show, modelContext: modelContext)
        try? modelContext.save()
        await NotificationService.shared.scheduleNotifications(for: show)
    }

    // MARK: - Movies

    func refreshAllMovies(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Movie>()
        guard let movies = try? modelContext.fetch(descriptor) else { return }
        let tracked = movies.filter { $0.tmdbID != nil && !$0.isArchived }
        guard !tracked.isEmpty else { return }

        for movie in tracked {
            guard let tmdbID = movie.tmdbID else { continue }
            guard let details = try? await TMDBService.shared.fetchMovieDetails(tmdbID: tmdbID) else { continue }
            movie.theatricalReleaseDate = details.usTheatricalDate() ?? .distantFuture
            movie.streamingReleaseDate = details.usStreamingDate()
            movie.tmdbStatus = details.status
            movie.updatedAt = .now
            if let providers = try? await TMDBService.shared.fetchWatchProviders(tmdbID: tmdbID, mediaType: "movie") {
                movie.watchProviderNames = providers.map(\.providerName)
            }
        }

        try? modelContext.save()
    }

    // MARK: - Sports

    func refreshAllTeams(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<SportTeam>()
        guard let teams = try? modelContext.fetch(descriptor) else { return }
        guard !teams.isEmpty else { return }

        for team in teams {
            await refreshTeam(team, modelContext: modelContext)
            try? await Task.sleep(for: .milliseconds(350)) // rate-limit free tier
        }

        try? modelContext.save()
    }

    func refreshTeam(_ team: SportTeam, modelContext: ModelContext) async {
        if team.dataSource == "espn" {
            await refreshESPNTeam(team, modelContext: modelContext)
        } else {
            await refreshTSDBTeam(team, modelContext: modelContext)
        }
    }

    private func refreshTSDBTeam(_ team: SportTeam, modelContext: ModelContext) async {
        guard let events = try? await TheSportsDBService.shared.fetchNextEvents(teamID: team.sportsDBID) else { return }

        var existingMap: [String: SportGame] = [:]
        for game in team.games { existingMap[game.sportsDBEventID] = game }

        for event in events {
            if let existing = existingMap[event.idEvent] {
                existing.result = event.result
                existing.isCompleted = event.isCompleted
                if let date = event.parsedGameDate { existing.gameDate = date }
            } else {
                let game = SportGame(
                    sportsDBEventID: event.idEvent,
                    title: event.strEvent,
                    homeTeam: event.strHomeTeam ?? "",
                    awayTeam: event.strAwayTeam ?? "",
                    gameDate: event.parsedGameDate ?? .distantFuture,
                    venue: event.strVenue,
                    round: event.strRound,
                    season: event.strSeason,
                    result: event.result,
                    isCompleted: event.isCompleted
                )
                game.team = team
                modelContext.insert(game)
            }
        }
    }

    private func refreshESPNTeam(_ team: SportTeam, modelContext: ModelContext) async {
        // leagueID stores "sport/league" path, e.g. "football/nfl"
        guard let leaguePath = team.leagueID, leaguePath.contains("/") else { return }
        let parts = leaguePath.split(separator: "/")
        guard parts.count == 2 else { return }
        let sport = String(parts[0])
        let league = String(parts[1])

        guard let events = try? await ESPNService.shared.fetchSchedule(
            espnTeamID: team.sportsDBID,
            sport: sport,
            leaguePath: league
        ) else { return }

        var existingMap: [String: SportGame] = [:]
        for game in team.games { existingMap[game.sportsDBEventID] = game }

        for event in events {
            let comp = event.competitions.first
            let isCompleted = comp?.status?.type?.completed ?? false
            let home = comp?.competitors.first(where: { $0.homeAway == "home" })?.team.displayName ?? ""
            let away = comp?.competitors.first(where: { $0.homeAway == "away" })?.team.displayName ?? ""

            var result: String? = nil
            if isCompleted,
               let homeScore = comp?.competitors.first(where: { $0.homeAway == "home" })?.score?.value,
               let awayScore = comp?.competitors.first(where: { $0.homeAway == "away" })?.score?.value {
                result = "\(Int(awayScore))–\(Int(homeScore))"
            }

            if let existing = existingMap[event.id] {
                existing.result = result
                existing.isCompleted = isCompleted
                if let date = event.parsedDate { existing.gameDate = date }
            } else {
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
                game.team = team
                modelContext.insert(game)
            }
        }
    }

    // MARK: - Anime

    func refreshAllAnime(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<AnimeShow>()
        guard let shows = try? modelContext.fetch(descriptor) else { return }
        guard !shows.isEmpty else { return }

        for show in shows {
            guard let detail = try? await AniListService.shared.fetchDetails(anilistID: show.anilistID) else { continue }

            // Update show metadata
            show.animeStatus = detail.status
            show.totalEpisodes = detail.totalEpisodes
            show.updatedAt = .now

            // Upsert episodes keyed by episode number
            var existingMap: [Int: AnimeEpisode] = [:]
            for ep in show.episodes { existingMap[ep.episodeNumber] = ep }

            for (epNum, airDate) in detail.airedEpisodes {
                if let existing = existingMap[epNum] {
                    existing.airDate = airDate
                } else {
                    let ep = AnimeEpisode(episodeNumber: epNum, airDate: airDate)
                    ep.show = show
                    modelContext.insert(ep)
                }
            }

            // Upsert next airing episode
            if let next = detail.nextAiringEpisode {
                let nextDate = Date(timeIntervalSince1970: Double(next.airingAt))
                if let existing = existingMap[next.episode] {
                    existing.airDate = nextDate
                } else if detail.airedEpisodes.first(where: { $0.episodeNumber == next.episode }) == nil {
                    let ep = AnimeEpisode(episodeNumber: next.episode, airDate: nextDate)
                    ep.show = show
                    modelContext.insert(ep)
                }
            }
        }

        try? modelContext.save()
    }

    // MARK: - Private

    /// Core upsert logic — fetches fresh data from TMDB and syncs into SwiftData.
    /// Throws on any network or decode failure.
    private func syncShow(_ show: Show, modelContext: ModelContext) async throws {
        guard let tmdbID = show.tmdbID else { return }

        let details = try await TMDBService.shared.fetchShowDetails(tmdbID: tmdbID)
        let freshEpisodes = try await TMDBService.shared.fetchAllEpisodes(tmdbID: tmdbID)

        // Sync show-level metadata that can change over time
        if let status = details.status, !status.isEmpty {
            show.showStatus = status
        }
        if let providers = try? await TMDBService.shared.fetchWatchProviders(tmdbID: tmdbID, mediaType: "tv") {
            show.watchProviderNames = providers.map(\.providerName)
        }

        // Build a lookup of existing episodes keyed by "season-episode"
        var existingMap: [String: Episode] = [:]
        for ep in show.episodes {
            existingMap["\(ep.seasonNumber)-\(ep.episodeNumber)"] = ep
        }

        var changed = false

        for tmdbEp in freshEpisodes {
            let key = "\(tmdbEp.seasonNumber)-\(tmdbEp.episodeNumber)"
            let freshDate = tmdbEp.parsedAirDate ?? Date.distantFuture

            if let existing = existingMap[key] {
                // Normalise the stored date to midnight local before comparing —
                // legacy entries may have been stored as midnight UTC, which differs
                // from the current midnight-local representation for the same calendar day.
                let normalised = Calendar.current.startOfDay(for: existing.airDate)
                if normalised != freshDate {
                    existing.airDate = freshDate
                    changed = true
                }
                // Update title if it was empty or has changed
                let freshTitle = tmdbEp.name ?? ""
                if existing.title != freshTitle && !freshTitle.isEmpty {
                    existing.title = freshTitle
                    changed = true
                }
            } else {
                // New episode not yet in the local store
                let episode = Episode(
                    seasonNumber: tmdbEp.seasonNumber,
                    episodeNumber: tmdbEp.episodeNumber,
                    title: tmdbEp.name ?? "",
                    airDate: freshDate,
                    isWatched: false
                )
                episode.show = show
                modelContext.insert(episode)
                changed = true
            }
        }

        if changed {
            show.updatedAt = .now
        }
    }
}
