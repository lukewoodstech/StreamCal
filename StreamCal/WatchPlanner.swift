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
                    .filter { !$0.isWatched && Calendar.current.isDateInToday($0.airDate) }
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
                        !$0.isWatched &&
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
                        !$0.isWatched &&
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
                    .filter { !$0.isWatched && $0.airDate == .distantFuture }
                    .map { (show: show, episode: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.show.title != rhs.show.title { return lhs.show.title < rhs.show.title }
                if lhs.episode.seasonNumber != rhs.episode.seasonNumber { return lhs.episode.seasonNumber < rhs.episode.seasonNumber }
                return lhs.episode.episodeNumber < rhs.episode.episodeNumber
            }
    }

    // MARK: - Calendar Sections

    struct CalendarDay {
        let date: Date
        let episodes: [Episode]
        var isToday: Bool { Calendar.current.isDateInToday(date) }
        var isPast: Bool { date < Calendar.current.startOfDay(for: .now) }
    }

    /// Groups episodes into calendar days: today through 60 days forward.
    /// Excludes archived shows, watched episodes, and TBA episodes.
    /// Sorted by date ascending.
    static func calendarDays(from episodes: [Episode]) -> [CalendarDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: 60, to: today) else { return [] }

        let windowed = episodes.filter {
            guard $0.show?.isArchived != true else { return false }
            return !$0.isWatched && $0.airDate != .distantFuture && $0.airDate >= today && $0.airDate < end
        }

        var dict: [Date: [Episode]] = [:]
        for ep in windowed {
            let day = cal.startOfDay(for: ep.airDate)
            dict[day, default: []].append(ep)
        }

        return dict
            .map { CalendarDay(date: $0.key, episodes: $0.value.sorted { $0.show?.title ?? "" < $1.show?.title ?? "" }) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Progress summaries

    static func progress(for show: Show) -> ShowProgress {
        ShowProgress(show: show)
    }

    static func progressList(for shows: [Show]) -> [ShowProgress] {
        shows.filter { !$0.isArchived }.map { ShowProgress(show: $0) }
    }

}
