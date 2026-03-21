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
        guard let events = try? await TheSportsDBService.shared.fetchNextEvents(teamID: team.sportsDBID) else { return }

        var existingMap: [String: SportGame] = [:]
        for game in team.games {
            existingMap[game.sportsDBEventID] = game
        }

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
