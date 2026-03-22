import Foundation
import UserNotifications
import SwiftData

@MainActor
final class NotificationService {

    static let shared = NotificationService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Permission

    /// Request notification permission. Returns true if granted.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Schedule

    /// Schedule notifications for each future unwatched episode, plus a same-day
    /// reminder for any episode the user has planned for tonight.
    /// Existing notifications for this show are replaced.
    func scheduleNotifications(for show: Show) async {
        let status = await authorizationStatus()
        guard status == .authorized else { return }
        guard show.notificationsEnabled else {
            await cancelNotifications(for: show)
            return
        }

        await cancelNotifications(for: show)

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // Air-date notifications for future unwatched episodes
        let futureEpisodes = show.episodes.filter {
            !$0.isWatched && $0.airDate > today && $0.airDate < Date.distantFuture
        }
        for episode in futureEpisodes {
            await scheduleAirDateNotification(for: episode, showTitle: show.title)
        }
    }

    /// Schedule notifications for all shows at once (e.g. after a background refresh).
    func scheduleNotifications(for shows: [Show]) async {
        for show in shows {
            await scheduleNotifications(for: show)
        }
        await cancelWeeklySummary()
        if weeklySummaryEnabled {
            await scheduleWeeklySummary(for: shows)
        }
    }

    // MARK: - Cancel

    func cancelNotifications(for show: Show) async {
        let ids = show.episodes.map { ep in
            notificationID(for: ep, suffix: "air")
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - User Preferences

    private var airReminderHour: Int {
        let stored = UserDefaults.standard.object(forKey: "airReminderHour")
        return (stored as? Int) ?? 9
    }

    private var weeklySummaryEnabled: Bool {
        UserDefaults.standard.bool(forKey: "weeklySummaryEnabled")
    }

    private var weeklySummaryHour: Int {
        let stored = UserDefaults.standard.object(forKey: "weeklySummaryHour")
        return (stored as? Int) ?? 20
    }

    // MARK: - Private

    private func scheduleAirDateNotification(for episode: Episode, showTitle: String) async {
        let id = notificationID(for: episode, suffix: "air")

        let content = UNMutableNotificationContent()
        content.title = showTitle
        content.body = episodeBody(episode)
        content.sound = .default

        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: episode.airDate)
        dateComponents.hour = airReminderHour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try? await center.add(request)
    }

    private func scheduleWeeklySummary(for shows: [Show]) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // Find the start of next Monday (the week that Sunday's summary previews)
        let weekday = cal.component(.weekday, from: today) // 1=Sun, 2=Mon ... 7=Sat
        let daysUntilMonday = weekday == 2 ? 7 : (weekday == 1 ? 1 : 9 - weekday)
        guard let nextMonday = cal.date(byAdding: .day, value: daysUntilMonday, to: today),
              let nextSunday = cal.date(byAdding: .day, value: -1, to: nextMonday),
              let weekEnd = cal.date(byAdding: .day, value: 6, to: nextMonday) else { return }

        // Collect episodes airing Mon–Sun of the coming week
        let weekEpisodes = shows.flatMap { $0.episodes }.filter {
            !$0.isWatched && $0.airDate >= nextMonday && $0.airDate <= weekEnd && $0.airDate != .distantFuture
        }

        guard !weekEpisodes.isEmpty else { return }

        // Group by show title, pick the earliest day for each
        var showDays: [(title: String, date: Date)] = []
        let byShow = Dictionary(grouping: weekEpisodes) { $0.show?.title ?? "Unknown" }
        for (title, eps) in byShow.sorted(by: { $0.key < $1.key }) {
            if let earliest = eps.sorted(by: { $0.airDate < $1.airDate }).first {
                showDays.append((title, earliest.airDate))
            }
        }
        showDays.sort { $0.date < $1.date }

        let body = weeklySummaryBody(showDays)

        let content = UNMutableNotificationContent()
        content.title = "This week on StreamCal"
        content.body = body
        content.sound = .default

        var dateComponents = cal.dateComponents([.year, .month, .day], from: nextSunday)
        dateComponents.hour = weeklySummaryHour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "streamcal-weekly-summary", content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func cancelWeeklySummary() async {
        center.removePendingNotificationRequests(withIdentifiers: ["streamcal-weekly-summary"])
    }

    private func weeklySummaryBody(_ showDays: [(title: String, date: Date)]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE" // "Mon", "Tue", etc.

        let visible = showDays.prefix(3)
        let rest = showDays.count - visible.count

        var parts = visible.map { "\($0.title) (\(formatter.string(from: $0.date)))" }
        if rest > 0 {
            parts.append("+\(rest) more")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Movie Notifications

    func scheduleNotification(for movie: Movie) async {
        let status = await authorizationStatus()
        guard status == .authorized, movie.notificationsEnabled else { return }
        guard movie.theatricalReleaseDate != .distantFuture,
              movie.theatricalReleaseDate > .now else { return }

        let id = movieNotificationID(movie)
        let content = UNMutableNotificationContent()
        content.title = movie.title
        content.body = "In theaters today"
        content.sound = .default

        var dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day], from: movie.theatricalReleaseDate
        )
        dateComponents.hour = airReminderHour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelMovieNotification(tmdbID: Int) {
        center.removePendingNotificationRequests(withIdentifiers: ["streamcal-movie-\(tmdbID)-theatrical"])
    }

    private func movieNotificationID(_ movie: Movie) -> String {
        if let tmdbID = movie.tmdbID { return "streamcal-movie-\(tmdbID)-theatrical" }
        return "streamcal-movie-\(movie.title.lowercased().replacingOccurrences(of: " ", with: "-"))-theatrical"
    }

    // MARK: - Game Notifications

    func scheduleNotifications(for team: SportTeam) async {
        let status = await authorizationStatus()
        guard status == .authorized, team.notificationsEnabled else { return }

        let minutesBefore = (UserDefaults.standard.object(forKey: "gameReminderMinutesBefore") as? Int) ?? 120
        let offset = TimeInterval(minutesBefore * 60)

        for game in team.games where !game.isCompleted && game.gameDate != .distantFuture && game.gameDate > .now {
            let fireDate = game.gameDate.addingTimeInterval(-offset)
            guard fireDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = game.displayTitle
            content.body = minutesBefore >= 60
                ? "Starts in \(minutesBefore / 60) hour\(minutesBefore / 60 == 1 ? "" : "s")"
                : "Starts in \(minutesBefore) min"
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = "streamcal-game-\(game.sportsDBEventID)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelGameNotifications(for team: SportTeam) {
        let ids = team.games.map { "streamcal-game-\($0.sportsDBEventID)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - ID helpers

    private func notificationID(for episode: Episode, suffix: String = "air") -> String {
        let showTitle = episode.show?.title ?? "unknown"
        return "streamcal-\(showTitle)-s\(episode.seasonNumber)e\(episode.episodeNumber)-\(suffix)"
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    private func episodeBody(_ episode: Episode) -> String {
        let code = "S\(String(format: "%02d", episode.seasonNumber))E\(String(format: "%02d", episode.episodeNumber))"
        if episode.title.isEmpty {
            return "\(code) airs today"
        }
        return "\(code) \u{2014} \(episode.title) airs today"
    }
}
