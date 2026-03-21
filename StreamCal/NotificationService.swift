import Foundation
import UserNotifications
import SwiftData

actor NotificationService {

    static let shared = NotificationService()

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

        await cancelNotifications(for: show)

        let today = Calendar.current.startOfDay(for: .now)

        // Air-date notifications for future unwatched episodes
        let futureEpisodes = show.episodes.filter {
            !$0.isWatched && $0.airDate > today && $0.airDate < Date.distantFuture
        }
        for episode in futureEpisodes {
            await scheduleAirDateNotification(for: episode, showTitle: show.title)
        }

        // Evening reminder for episodes planned for tonight (8 PM)
        let plannedTonight = show.episodes.filter {
            !$0.isWatched && $0.isPlannedToday
        }
        for episode in plannedTonight {
            await schedulePlanNotification(for: episode, showTitle: show.title)
        }
    }

    /// Schedule notifications for all shows at once (e.g. after a background refresh).
    func scheduleNotifications(for shows: [Show]) async {
        for show in shows {
            await scheduleNotifications(for: show)
        }
    }

    // MARK: - Cancel

    func cancelNotifications(for show: Show) async {
        let ids = show.episodes.flatMap { ep in
            [notificationID(for: ep, suffix: "air"), notificationID(for: ep, suffix: "plan")]
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - User Preferences

    private var airReminderHour: Int {
        let stored = UserDefaults.standard.object(forKey: "airReminderHour")
        return (stored as? Int) ?? 9
    }

    private var planReminderHour: Int {
        let stored = UserDefaults.standard.object(forKey: "planReminderHour")
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

    private func schedulePlanNotification(for episode: Episode, showTitle: String) async {
        let id = notificationID(for: episode, suffix: "plan")

        let content = UNMutableNotificationContent()
        content.title = "Tonight: \(showTitle)"
        content.body = "You planned to watch \(episode.displayTitle) tonight."
        content.sound = .default

        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        dateComponents.hour = planReminderHour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try? await center.add(request)
    }

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
