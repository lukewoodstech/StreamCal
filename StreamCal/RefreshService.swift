import Foundation
import SwiftData

/// Silently refreshes episode data from TMDB for all tracked shows on app launch.
/// Only adds new episodes — never removes or overwrites existing ones.
@MainActor
final class RefreshService {

    static let shared = RefreshService()

    /// Call once on app launch. Fetches fresh episodes for every show that has a tmdbID,
    /// inserts any new ones, then reschedules notifications.
    func refreshAllShows(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Show>()
        guard let shows = try? modelContext.fetch(descriptor) else { return }

        let trackedShows = shows.filter { $0.tmdbID != nil && !$0.isArchived }
        guard !trackedShows.isEmpty else { return }

        for show in trackedShows {
            await refreshShow(show, modelContext: modelContext)
        }

        // Reschedule all notifications with the latest episode data
        await NotificationService.shared.scheduleNotifications(for: trackedShows)
    }

    // MARK: - Private

    private func refreshShow(_ show: Show, modelContext: ModelContext) async {
        guard let tmdbID = show.tmdbID else { return }

        do {
            let freshEpisodes = try await TMDBService.shared.fetchAllEpisodes(tmdbID: tmdbID)

            let existing = Set(show.episodes.map { "\($0.seasonNumber)-\($0.episodeNumber)" })
            var addedAny = false

            for ep in freshEpisodes {
                let key = "\(ep.seasonNumber)-\(ep.episodeNumber)"
                guard !existing.contains(key) else { continue }

                let airDate = ep.parsedAirDate ?? Date.distantFuture
                let episode = Episode(
                    seasonNumber: ep.seasonNumber,
                    episodeNumber: ep.episodeNumber,
                    title: ep.name ?? "",
                    airDate: airDate,
                    isWatched: false
                )
                episode.show = show
                modelContext.insert(episode)
                addedAny = true
            }

            if addedAny {
                show.updatedAt = .now
            }
        } catch {
            // Silently fail — background refresh, don't surface to user
        }
    }
}
