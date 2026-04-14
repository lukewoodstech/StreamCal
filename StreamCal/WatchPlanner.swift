import Foundation
import SwiftData

// MARK: - Show Progress Summary

/// Pure value type describing the computed watch state for a single show.
/// Created by WatchPlanner — never stored in SwiftData.
struct ShowProgress {
    let show: Show

    // Next episode the user should watch (backlog or future)
    var nextToWatch: Episode? { show.nextToWatch }

    // Next episode that hasn't aired yet
    var nextUpcoming: Episode? { show.nextUpcomingEpisode }

    // All unwatched aired episodes in order
    var backlog: [Episode] { show.backlogEpisodes }

    var backlogCount: Int { show.backlogCount }
    var hasBacklog: Bool { show.hasWatchBacklog }
    var isFullyCaughtUp: Bool { show.isFullyCaughtUp }
    var lastWatched: Episode? { show.lastWatchedEpisode }

    /// Human-readable status line for Library rows.
    /// Leads with upcoming/airing info — backlog is secondary context only.
    var progressLabel: String {
        let cal = Calendar.current

        // Next upcoming episode is the primary signal
        if let upcoming = nextUpcoming {
            if upcoming.airDate == .distantFuture { return "Next episode: TBA" }
            if cal.isDateInToday(upcoming.airDate) { return "New episode today!" }
            if cal.isDateInTomorrow(upcoming.airDate) { return "New episode tomorrow" }
            return "Next: \(upcoming.airDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        }

        // No upcoming episodes
        if show.episodes.isEmpty { return "No episodes yet" }
        if isFullyCaughtUp { return "All caught up" }

        // No announced next season yet
        let status = show.showStatus ?? ""
        if status == "Ended" { return "Series ended" }
        if status == "Returning Series" || status == "In Production" { return "Between seasons" }

        return "Up to date"
    }

    /// Detailed line shown below the main label.
    var progressDetail: String? {
        if let last = lastWatched, backlogCount == 0, nextUpcoming != nil {
            return "Up to date through \(last.displayTitle)"
        }
        return nil
    }
}

// MARK: - Watch Planner

/// Centralises all episode/show derivation logic.
/// Views inject their @Query results here to get organised sections — no
/// classification logic leaks into views.
@MainActor
final class WatchPlanner {

    // MARK: - New Episodes Today

    /// Shows releasing their next unwatched episode today.
    static func newEpisodesToday(from shows: [Show]) -> [(show: Show, episode: Episode)] {
        shows
            .filter { !$0.isArchived }
            .compactMap { show -> (Show, Episode)? in
                guard let ep = show.nextUpcomingEpisode,
                      Calendar.current.isDateInToday(ep.airDate) else { return nil }
                return (show, ep)
            }
            .sorted { $0.show.title < $1.show.title }
    }

    // MARK: - All Caught Up Shows

    static func caughtUpShows(from shows: [Show]) -> [Show] {
        shows
            .filter { !$0.isArchived && $0.isFullyCaughtUp }
    }

    // MARK: - Next Up: Future-release sections

    /// Episodes airing today that are unwatched, from non-archived shows.
    /// One episode per show (the first unwatched one airing today).
    static func nextUpAiringToday(from shows: [Show]) -> [(show: Show, episode: Episode)] {
        shows
            .filter { !$0.isArchived }
            .compactMap { show -> (Show, Episode)? in
                let ep = show.episodes
                    .filter { Calendar.current.isDateInToday($0.airDate) }
                    .sorted {
                        if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
                        return $0.episodeNumber < $1.episodeNumber
                    }
                    .first
                guard let ep else { return nil }
                return (show, ep)
            }
            .sorted { $0.show.title < $1.show.title }
    }

    /// Unwatched episodes airing strictly this week (tomorrow through 6 days from now),
    /// from non-archived shows. One episode per show per day, sorted by air date then show title.
    static func nextUpThisWeek(from shows: [Show]) -> [(show: Show, episode: Episode)] {
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
        guard let endOfWeek = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: .now)) else { return [] }

        return shows
            .filter { !$0.isArchived }
            .flatMap { show in
                show.episodes
                    .filter {
                        $0.airDate != .distantFuture &&
                        $0.airDate >= tomorrow &&
                        $0.airDate < endOfWeek
                    }
                    .map { (show: show, episode: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.episode.airDate != rhs.episode.airDate { return lhs.episode.airDate < rhs.episode.airDate }
                return lhs.show.title < rhs.show.title
            }
    }

    /// Unwatched episodes airing more than 7 days from now (no TBA),
    /// from non-archived shows. All matching episodes, sorted by air date then show title.
    static func nextUpComingSoon(from shows: [Show]) -> [(show: Show, episode: Episode)] {
        let cal = Calendar.current
        guard let beyond = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: .now)) else { return [] }

        return shows
            .filter { !$0.isArchived }
            .flatMap { show in
                show.episodes
                    .filter {
                        $0.airDate != .distantFuture &&
                        $0.airDate >= beyond
                    }
                    .map { (show: show, episode: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.episode.airDate != rhs.episode.airDate { return lhs.episode.airDate < rhs.episode.airDate }
                return lhs.show.title < rhs.show.title
            }
    }

    /// Unwatched TBA episodes from non-archived shows, sorted by show title then season/episode.
    static func nextUpDateTBA(from shows: [Show]) -> [(show: Show, episode: Episode)] {
        shows
            .filter { !$0.isArchived }
            .flatMap { show in
                show.episodes
                    .filter { $0.airDate == .distantFuture }
                    .map { (show: show, episode: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.show.title != rhs.show.title { return lhs.show.title < rhs.show.title }
                if lhs.episode.seasonNumber != rhs.episode.seasonNumber { return lhs.episode.seasonNumber < rhs.episode.seasonNumber }
                return lhs.episode.episodeNumber < rhs.episode.episodeNumber
            }
    }

    // MARK: - Movie Sections

    /// Non-archived movies that have been theatrically released.
    static func moviesInTheaters(from movies: [Movie]) -> [Movie] {
        movies.filter { !$0.isArchived && $0.releaseStatus == .released }
    }

    /// Non-archived movies with a known upcoming theatrical release date.
    static func moviesComingSoon(from movies: [Movie]) -> [Movie] {
        movies.filter { !$0.isArchived && $0.releaseStatus == .comingSoon && $0.theatricalReleaseDate != .distantFuture }
    }

    /// Non-archived movies available on streaming, sorted by streaming release date ascending.
    static func moviesStreamingSoon(from movies: [Movie]) -> [Movie] {
        movies
            .filter { !$0.isArchived && $0.releaseStatus == .streaming }
            .sorted { ($0.streamingReleaseDate ?? .distantFuture) < ($1.streamingReleaseDate ?? .distantFuture) }
    }

    // MARK: - Game Sections

    /// Incomplete games scheduled for today.
    static func gamesToday(from games: [SportGame]) -> [SportGame] {
        games.filter { !$0.isCompleted && Calendar.current.isDateInToday($0.gameDate) }
    }

    /// Incomplete games after today through the next 7 days (exclusive of today).
    static func gamesThisWeek(from games: [SportGame]) -> [SportGame] {
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

    /// Incomplete games beyond the next 7 days, capped at 20 results.
    static func gamesUpcoming(from games: [SportGame]) -> [SportGame] {
        let cal = Calendar.current
        let now = Date.now
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now))!
        return Array(games.filter {
            !$0.isCompleted && $0.gameDate > weekEnd && $0.gameDate != .distantFuture
        }.prefix(20))
    }

    // MARK: - Calendar Sections

    struct CalendarDay {
        let date: Date
        let episodes: [Episode]
        var movies: [Movie] = []
        var games: [SportGame] = []
        var animeEpisodes: [AnimeEpisode] = []
        var isToday: Bool { Calendar.current.isDateInToday(date) }
        var isPast: Bool { date < Calendar.current.startOfDay(for: .now) }
        var isEmpty: Bool { episodes.isEmpty && movies.isEmpty && games.isEmpty && animeEpisodes.isEmpty }
    }

    /// Groups episodes, movies, games, and anime into calendar days from today forward with no upper limit.
    /// Excludes archived shows/movies, watched episodes, TBA dates, and past dates.
    /// Sorted by date ascending.
    static func calendarDays(
        from episodes: [Episode],
        movies: [Movie] = [],
        games: [SportGame] = [],
        anime: [AnimeEpisode] = []
    ) -> [CalendarDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // Episodes
        let windowed = episodes.filter {
            guard $0.show?.isArchived != true else { return false }
            return $0.airDate != .distantFuture && $0.airDate >= today
        }
        var episodeDict: [Date: [Episode]] = [:]
        for ep in windowed {
            let day = cal.startOfDay(for: ep.airDate)
            episodeDict[day, default: []].append(ep)
        }

        // Movies
        let windowedMovies = movies.filter {
            guard !$0.isArchived else { return false }
            let date = $0.primaryCalendarDate
            return date != .distantFuture && date >= today
        }
        var movieDict: [Date: [Movie]] = [:]
        for movie in windowedMovies {
            let day = cal.startOfDay(for: movie.primaryCalendarDate)
            movieDict[day, default: []].append(movie)
        }

        // Games
        let windowedGames = games.filter {
            $0.gameDate != .distantFuture && $0.gameDate >= today && !$0.isCompleted
        }
        var gameDict: [Date: [SportGame]] = [:]
        for game in windowedGames {
            let day = cal.startOfDay(for: game.gameDate)
            gameDict[day, default: []].append(game)
        }

        // Anime episodes
        let windowedAnime = anime.filter {
            guard $0.show?.isArchived != true else { return false }
            return $0.airDate != .distantFuture && $0.airDate >= today
        }
        var animeDict: [Date: [AnimeEpisode]] = [:]
        for ep in windowedAnime {
            let day = cal.startOfDay(for: ep.airDate)
            animeDict[day, default: []].append(ep)
        }

        // Merge all dates
        let allDates = Set(episodeDict.keys).union(movieDict.keys).union(gameDict.keys).union(animeDict.keys)
        return allDates.map { date in
            CalendarDay(
                date: date,
                episodes: (episodeDict[date] ?? []).sorted { $0.show?.title ?? "" < $1.show?.title ?? "" },
                movies: (movieDict[date] ?? []).sorted { $0.title < $1.title },
                games: (gameDict[date] ?? []).sorted { $0.gameDate < $1.gameDate },
                animeEpisodes: (animeDict[date] ?? []).sorted { ($0.show?.displayTitle ?? "") < ($1.show?.displayTitle ?? "") }
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Progress summaries

    static func progress(for show: Show) -> ShowProgress {
        ShowProgress(show: show)
    }

    static func progressList(for shows: [Show]) -> [ShowProgress] {
        shows.filter { !$0.isArchived }.map { ShowProgress(show: $0) }
    }

}
