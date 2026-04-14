import Foundation
import SwiftData

// MARK: - AnimeShow

@Model
final class AnimeShow {

    var anilistID: Int
    var titleRomaji: String
    var titleEnglish: String?
    var coverImageURL: String?
    var overview: String?
    var animeStatus: String          // "RELEASING" | "FINISHED" | "NOT_YET_RELEASED" | "CANCELLED" | "HIATUS"
    var totalEpisodes: Int?
    var genres: [String]
    var isArchived: Bool = false
    var notificationsEnabled: Bool = true
    /// User has marked this anime as already seen — used only for AI context, never shown in UI.
    var isSeen: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade) var episodes: [AnimeEpisode] = []

    init(anilistID: Int,
         titleRomaji: String,
         titleEnglish: String? = nil,
         coverImageURL: String? = nil,
         overview: String? = nil,
         animeStatus: String = "RELEASING",
         totalEpisodes: Int? = nil,
         genres: [String] = []) {
        self.anilistID = anilistID
        self.titleRomaji = titleRomaji
        self.titleEnglish = titleEnglish
        self.coverImageURL = coverImageURL
        self.overview = overview
        self.animeStatus = animeStatus
        self.totalEpisodes = totalEpisodes
        self.genres = genres
    }

    var displayTitle: String { titleEnglish ?? titleRomaji }

    var posterImageURL: URL? {
        guard let s = coverImageURL else { return nil }
        return URL(string: s)
    }

    var nextUpcomingEpisode: AnimeEpisode? {
        let today = Calendar.current.startOfDay(for: .now)
        return episodes
            .filter { !$0.isWatched && $0.airDate >= today && $0.airDate != .distantFuture }
            .min(by: { $0.airDate < $1.airDate })
    }

    var backlogEpisodes: [AnimeEpisode] {
        let today = Calendar.current.startOfDay(for: .now)
        return episodes
            .filter { !$0.isWatched && $0.airDate < today && $0.airDate != .distantFuture }
            .sorted { $0.airDate < $1.airDate }
    }

    var watchedCount: Int { episodes.filter { $0.isWatched }.count }

    var episodeProgress: String {
        let watched = watchedCount
        if let total = totalEpisodes {
            return "Ep \(watched)/\(total)"
        }
        return "Ep \(watched)"
    }
}

// MARK: - AnimeEpisode

@Model
final class AnimeEpisode {

    var episodeNumber: Int
    var airDate: Date
    var isWatched: Bool = false
    var createdAt: Date = Date.now

    var show: AnimeShow?

    init(episodeNumber: Int, airDate: Date, isWatched: Bool = false) {
        self.episodeNumber = episodeNumber
        self.airDate = airDate
        self.isWatched = isWatched
    }

    var displayTitle: String { "Episode \(episodeNumber)" }
}
