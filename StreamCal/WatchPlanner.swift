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

    // Episode explicitly planned for today
    var plannedToday: Episode? { show.plannedTodayEpisode }

    var backlogCount: Int { show.backlogCount }
    var hasBacklog: Bool { show.hasWatchBacklog }
    var isFullyCaughtUp: Bool { show.isFullyCaughtUp }
    var lastWatched: Episode? { show.lastWatchedEpisode }

    /// Human-readable progress line for Library rows.
    var progressLabel: String {
        if let planned = plannedToday {
            return "Planned tonight · \(planned.displayTitle)"
        }
        if hasBacklog {
            let count = backlogCount
            if let next = nextToWatch {
                return count == 1
                    ? "Watch next: \(next.displayTitle)"
                    : "Backlog: \(count) eps · \(next.displayTitle)"
            }
            return "Backlog: \(count) eps"
        }
        if let upcoming = nextUpcoming {
            if upcoming.airDate == .distantFuture { return "Next episode: TBA" }
            let cal = Calendar.current
            if cal.isDateInToday(upcoming.airDate) { return "New episode today!" }
            if cal.isDateInTomorrow(upcoming.airDate) { return "New episode tomorrow" }
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE MMM d"
            return "Next: \(formatter.string(from: upcoming.airDate))"
        }
        if isFullyCaughtUp { return "All caught up" }
        if show.episodes.isEmpty { return "No episodes yet" }
        return "Up to date"
    }

    /// Detailed progress line such as "Up to date through S2E5"
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

    // MARK: - Tonight's Plan

    /// Episodes explicitly planned for today, unwatched, sorted by season/ep.
    static func tonightsPlan(from shows: [Show]) -> [(show: Show, episode: Episode)] {
        shows
            .filter { !$0.isArchived }
            .compactMap { show -> (Show, Episode)? in
                guard let ep = show.plannedTodayEpisode else { return nil }
                return (show, ep)
            }
            .sorted { lhs, rhs in
                if lhs.0.title != rhs.0.title { return lhs.0.title < rhs.0.title }
                if lhs.1.seasonNumber != rhs.1.seasonNumber { return lhs.1.seasonNumber < rhs.1.seasonNumber }
                return lhs.1.episodeNumber < rhs.1.episodeNumber
            }
    }

    // MARK: - Continue Watching (backlog — next unwatched aired episode per show)

    /// One entry per show: the next unwatched aired episode.
    /// Excludes shows that are planned for today (they're already in tonightsPlan).
    static func continueWatching(from shows: [Show]) -> [(show: Show, episode: Episode)] {
        return shows
            .filter { !$0.isArchived }
            .compactMap { show -> (Show, Episode)? in
                // Skip shows already covered by tonight's plan
                guard show.plannedTodayEpisode == nil else { return nil }
                guard let ep = show.backlogEpisodes.first else { return nil }
                // Exclude today's airings — those go in "New Episodes Today"
                guard !Calendar.current.isDateInToday(ep.airDate) else { return nil }
                return (show, ep)
            }
            .sorted { $0.show.title < $1.show.title }
    }

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

    // MARK: - Coming Soon (next 7 days, exclusive of today)

    /// Shows with a future episode in the next 7 days (not today, not backlog).
    static func comingSoon(from shows: [Show]) -> [(show: Show, episode: Episode)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let cutoff = cal.date(byAdding: .day, value: 7, to: today) else { return [] }

        return shows
            .filter { !$0.isArchived }
            .compactMap { show -> (Show, Episode)? in
                guard let ep = show.nextUpcomingEpisode else { return nil }
                guard ep.airDate > today, ep.airDate < cutoff else { return nil }
                guard !cal.isDateInToday(ep.airDate) else { return nil }
                return (show, ep)
            }
            .sorted { $0.episode.airDate < $1.episode.airDate }
    }

    // MARK: - All Caught Up Shows

    static func caughtUpShows(from shows: [Show]) -> [Show] {
        shows
            .filter { !$0.isArchived && $0.isFullyCaughtUp }
    }

    // MARK: - Calendar Sections

    struct CalendarDay {
        let date: Date
        let episodes: [Episode]
        var isToday: Bool { Calendar.current.isDateInToday(date) }
        var isPast: Bool { date < Calendar.current.startOfDay(for: .now) }
    }

    /// Groups episodes into calendar days: 7 days back through 60 days forward.
    /// TBA episodes excluded. Sorted by date ascending.
    static func calendarDays(from episodes: [Episode]) -> [CalendarDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard
            let start = cal.date(byAdding: .day, value: -7, to: today),
            let end = cal.date(byAdding: .day, value: 60, to: today)
        else { return [] }

        let windowed = episodes.filter {
            $0.airDate != .distantFuture && $0.airDate >= start && $0.airDate < end
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

    // MARK: - Planning helpers

    static func planEpisode(_ episode: Episode, for date: Date) {
        episode.plannedDate = Calendar.current.startOfDay(for: date)
    }

    static func clearPlan(for episode: Episode) {
        episode.plannedDate = nil
    }

    static func planTonight(_ episode: Episode) {
        planEpisode(episode, for: .now)
    }

    static func planTomorrow(_ episode: Episode) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        planEpisode(episode, for: tomorrow)
    }

    static func planThisWeekend(_ episode: Episode) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today)
        // Saturday = 7, Sunday = 1
        let daysUntilSaturday: Int
        if weekday == 7 { daysUntilSaturday = 0 }
        else if weekday == 1 { daysUntilSaturday = 6 }
        else { daysUntilSaturday = 7 - weekday }
        let saturday = cal.date(byAdding: .day, value: daysUntilSaturday, to: today) ?? today
        planEpisode(episode, for: saturday)
    }
}
