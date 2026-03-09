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

    /// Human-readable status line for Library rows.
    /// Leads with upcoming/airing info — backlog is secondary context only.
    var progressLabel: String {
        let cal = Calendar.current

        // Next upcoming episode is the primary signal
        if let upcoming = nextUpcoming {
            if upcoming.airDate == .distantFuture { return "Next episode: TBA" }
            if cal.isDateInToday(upcoming.airDate) { return "New episode today!" }
            if cal.isDateInTomorrow(upcoming.airDate) { return "New episode tomorrow" }
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE MMM d"
            return "Next: \(formatter.string(from: upcoming.airDate))"
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

    // MARK: - Up Next (all future episodes, exclusive of today)

    /// One entry per show: the next episode airing after today.
    /// Excludes today's episodes (those are in newEpisodesToday) and
    /// excludes shows already covered by tonight's plan.
    /// TBA episodes are included but sorted to the end.
    static func upNext(from shows: [Show]) -> [(show: Show, episode: Episode)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        return shows
            .filter { !$0.isArchived }
            .compactMap { show -> (Show, Episode)? in
                guard show.plannedTodayEpisode == nil else { return nil }
                guard let ep = show.nextUpcomingEpisode else { return nil }
                guard !cal.isDateInToday(ep.airDate) else { return nil }
                guard ep.airDate > today || ep.airDate == .distantFuture else { return nil }
                return (show, ep)
            }
            .sorted { lhs, rhs in
                let lTBA = lhs.episode.airDate == .distantFuture
                let rTBA = rhs.episode.airDate == .distantFuture
                if lTBA && rTBA { return lhs.show.title < rhs.show.title }
                if lTBA { return false }
                if rTBA { return true }
                return lhs.episode.airDate < rhs.episode.airDate
            }
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

    /// Groups episodes into calendar days: 7 days back through 60 days forward.
    /// Excludes archived shows. TBA episodes excluded from dated sections.
    /// Sorted by date ascending.
    static func calendarDays(from episodes: [Episode]) -> [CalendarDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard
            let start = cal.date(byAdding: .day, value: -7, to: today),
            let end = cal.date(byAdding: .day, value: 60, to: today)
        else { return [] }

        // DIAG: show what the filter sees
        print("[StreamCal Diag] calendarDays — \(episodes.count) total episodes in @Query")
        print("[StreamCal Diag] Window: \(start) → \(end)")
        var droppedArchived = 0, droppedTBA = 0, droppedOutsideWindow = 0, passed = 0
        for ep in episodes {
            if ep.show?.isArchived == true { droppedArchived += 1; continue }
            if ep.airDate == .distantFuture { droppedTBA += 1; continue }
            if ep.airDate < start || ep.airDate >= end { droppedOutsideWindow += 1; continue }
            passed += 1
            if ep.airDate >= today {
                print("[StreamCal Diag]   PASS (future): \(ep.show?.title ?? "?") S\(ep.seasonNumber)E\(ep.episodeNumber) \(ep.airDate) watched=\(ep.isWatched)")
            }
        }
        print("[StreamCal Diag] Filter result — passed=\(passed) droppedTBA=\(droppedTBA) droppedOutsideWindow=\(droppedOutsideWindow) droppedArchived=\(droppedArchived)")

        let windowed = episodes.filter {
            guard $0.show?.isArchived != true else { return false }
            return $0.airDate != .distantFuture && $0.airDate >= start && $0.airDate < end
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

    /// Returns unwatched TBA episodes from non-archived shows — shown separately
    /// in the calendar so future episodes aren't silently hidden.
    static func tbaEpisodes(from episodes: [Episode]) -> [Episode] {
        episodes.filter {
            $0.airDate == .distantFuture &&
            !$0.isWatched &&
            $0.show?.isArchived != true
        }
        .sorted {
            let lhsShow = $0.show?.title ?? ""
            let rhsShow = $1.show?.title ?? ""
            if lhsShow != rhsShow { return lhsShow < rhsShow }
            if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
            return $0.episodeNumber < $1.episodeNumber
        }
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
