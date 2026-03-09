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
            await refreshShow(show, modelContext: modelContext)
        }

        await NotificationService.shared.scheduleNotifications(for: trackedShows)
    }

    // MARK: - Private

    private func refreshShow(_ show: Show, modelContext: ModelContext) async {
        guard let tmdbID = show.tmdbID else { return }

        do {
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

            // DIAG: log what TMDB returned for future/TBA episodes
            let today = Date()
            let futureTMDB = freshEpisodes.filter { $0.parsedAirDate != nil && $0.parsedAirDate! > today }
            let tbaTMDB = freshEpisodes.filter { $0.parsedAirDate == nil }
            print("[StreamCal Diag] \(show.title) — TMDB returned \(freshEpisodes.count) total eps, \(futureTMDB.count) future, \(tbaTMDB.count) nil airDate (→ distantFuture)")
            for ep in futureTMDB.prefix(5) {
                print("[StreamCal Diag]   Future ep: S\(ep.seasonNumber)E\(ep.episodeNumber) rawAirDate='\(ep.airDate ?? "nil")' parsed=\(ep.parsedAirDate.map { "\($0)" } ?? "nil")")
            }

            for tmdbEp in freshEpisodes {
                let key = "\(tmdbEp.seasonNumber)-\(tmdbEp.episodeNumber)"
                let freshDate = tmdbEp.parsedAirDate ?? Date.distantFuture

                if let existing = existingMap[key] {
                    // Update air date if TMDB has a different (more precise) value
                    if existing.airDate != freshDate {
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

            // DIAG: log what ended up stored for this show after the refresh
            let storedFuture = show.episodes.filter { $0.airDate > today && $0.airDate != .distantFuture }
            let storedTBA = show.episodes.filter { $0.airDate == .distantFuture }
            print("[StreamCal Diag] \(show.title) — after refresh: \(show.episodes.count) stored eps, \(storedFuture.count) with real future dates, \(storedTBA.count) TBA")
            for ep in storedFuture.prefix(5) {
                print("[StreamCal Diag]   Stored future: S\(ep.seasonNumber)E\(ep.episodeNumber) airDate=\(ep.airDate) isWatched=\(ep.isWatched)")
            }
        } catch {
            print("[StreamCal Diag] \(show.title) — refresh FAILED: \(error)")
        }
    }
}
