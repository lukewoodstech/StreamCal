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

        try? modelContext.save()
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
        } catch {
            print("[StreamCal Diag] \(show.title) — refresh FAILED: \(error)")
        }
    }
}
