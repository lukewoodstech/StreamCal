import Foundation
import SwiftData

enum StreamingPlatform: String, CaseIterable, Codable {
    case netflix = "Netflix"
    case hulu = "Hulu"
    case disneyPlus = "Disney+"
    case max = "Max"
    case appleTV = "Apple TV+"
    case amazonPrime = "Prime Video"
    case peacock = "Peacock"
    case paramountPlus = "Paramount+"
    case other = "Other"
}

@Model
final class Show {
    var title: String
    var platform: String
    var notes: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    // TMDB metadata — nil until the show is imported from search
    var tmdbID: Int?
    var posterURL: String?
    var overview: String?
    var showStatus: String?

    @Relationship(deleteRule: .cascade, inverse: \Episode.show)
    var episodes: [Episode] = []

    init(
        title: String,
        platform: String = StreamingPlatform.other.rawValue,
        notes: String = "",
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tmdbID: Int? = nil,
        posterURL: String? = nil,
        overview: String? = nil,
        showStatus: String? = nil
    ) {
        self.title = title
        self.platform = platform
        self.notes = notes
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tmdbID = tmdbID
        self.posterURL = posterURL
        self.overview = overview
        self.showStatus = showStatus
    }

    /// The earliest unwatched episode that hasn't aired yet, including TBA episodes.
    var nextUpcomingEpisode: Episode? {
        let today = Calendar.current.startOfDay(for: .now)
        // Include distantFuture (TBA) episodes — sort them after real dates
        return episodes
            .filter { !$0.isWatched && ($0.airDate >= today || $0.airDate == .distantFuture) }
            .sorted {
                if $0.airDate == .distantFuture && $1.airDate == .distantFuture {
                    if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
                    return $0.episodeNumber < $1.episodeNumber
                }
                if $0.airDate == .distantFuture { return false }
                if $1.airDate == .distantFuture { return true }
                return $0.airDate < $1.airDate
            }
            .first
    }

    var nextEpisodeDateText: String? {
        guard let ep = nextUpcomingEpisode else { return nil }
        if ep.airDate == .distantFuture { return "TBA" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: ep.airDate)
    }

    var sortedEpisodes: [Episode] {
        episodes.sorted {
            if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
            return $0.episodeNumber < $1.episodeNumber
        }
    }
}

@Model
final class Episode {
    var seasonNumber: Int
    var episodeNumber: Int
    var title: String
    var airDate: Date
    var isWatched: Bool
    var createdAt: Date

    var show: Show?

    init(
        seasonNumber: Int = 1,
        episodeNumber: Int = 1,
        title: String = "",
        airDate: Date = .now,
        isWatched: Bool = false,
        createdAt: Date = .now
    ) {
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.airDate = airDate
        self.isWatched = isWatched
        self.createdAt = createdAt
    }

    var displayTitle: String {
        let code = "S\(String(format: "%02d", seasonNumber))E\(String(format: "%02d", episodeNumber))"
        return title.isEmpty ? code : "\(code) — \(title)"
    }
}
