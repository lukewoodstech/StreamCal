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

    /// Schedule a morning notification for each future unwatched episode.
    /// Existing notifications for this show are replaced.
    func scheduleNotifications(for show: Show) async {
        let status = await authorizationStatus()
        guard status == .authorized else { return }

        // Clear existing notifications for this show first
        await cancelNotifications(for: show)

        let today = Calendar.current.startOfDay(for: .now)
        let futureEpisodes = show.episodes.filter {
            !$0.isWatched && $0.airDate >= today && $0.airDate < Date.distantFuture
        }

        for episode in futureEpisodes {
            await scheduleNotification(for: episode, showTitle: show.title)
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
        let ids = show.episodes.map { notificationID(for: $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Private

    private func scheduleNotification(for episode: Episode, showTitle: String) async {
        let id = notificationID(for: episode)

        let content = UNMutableNotificationContent()
        content.title = showTitle
        content.body = episodeBody(episode)
        content.sound = .default

        // Fire at 9am on the episode's air date
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: episode.airDate)
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try? await center.add(request)
    }

    private func notificationID(for episode: Episode) -> String {
        // Stable ID from show title + season + episode number
        let showTitle = episode.show?.title ?? "unknown"
        return "streamcal-\(showTitle)-s\(episode.seasonNumber)e\(episode.episodeNumber)"
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
