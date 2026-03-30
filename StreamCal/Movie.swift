import Foundation
import SwiftData

// MARK: - Movie Release Status

enum MovieReleaseStatus {
    case announced    // TBA or > 90 days out
    case comingSoon   // 1–90 days until theatrical
    case released     // theatrical date passed, streaming not yet set
    case streaming    // streaming date has passed
    case watched      // user marked as watched
}

// MARK: - Movie

@Model
final class Movie {
    var title: String
    var tmdbID: Int?
    var posterURL: String?
    var overview: String?
    var tagline: String?
    var genres: [String] = []
    var theatricalReleaseDate: Date         // .distantFuture = TBA
    var streamingReleaseDate: Date?         // TMDB digital release (type 4)
    var tmdbStatus: String?                 // "Released", "In Production", etc.
    var isWatched: Bool = false
    var watchedAt: Date?
    var platforms: [String] = []
    /// Streaming service names from TMDB watch/providers (US flatrate). Populated on import and refresh.
    var watchProviderNames: [String] = []
    var notificationsEnabled: Bool = true
    var isArchived: Bool = false
    var createdAt: Date
    var updatedAt: Date

    init(
        title: String,
        tmdbID: Int? = nil,
        posterURL: String? = nil,
        overview: String? = nil,
        tagline: String? = nil,
        genres: [String] = [],
        theatricalReleaseDate: Date = .distantFuture,
        streamingReleaseDate: Date? = nil,
        tmdbStatus: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.title = title
        self.tmdbID = tmdbID
        self.posterURL = posterURL
        self.overview = overview
        self.tagline = tagline
        self.genres = genres
        self.theatricalReleaseDate = theatricalReleaseDate
        self.streamingReleaseDate = streamingReleaseDate
        self.tmdbStatus = tmdbStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Derives display section for MoviesView and calendar dot color.
    var releaseStatus: MovieReleaseStatus {
        if isWatched { return .watched }
        let today = Calendar.current.startOfDay(for: .now)
        if let streaming = streamingReleaseDate, streaming <= today { return .streaming }
        if theatricalReleaseDate == .distantFuture { return .announced }
        if theatricalReleaseDate <= today { return .released }
        let days = Calendar.current.dateComponents([.day], from: today, to: theatricalReleaseDate).day ?? Int.max
        return days <= 90 ? .comingSoon : .announced
    }

    /// Watch providers matched to StreamingPlatform cases for UI display.
    var matchedStreamingPlatforms: [StreamingPlatform] {
        watchProviderNames.compactMap { StreamingPlatform.match(providerName: $0) }
    }

    var posterImageURL: URL? {
        guard let s = posterURL else { return nil }
        return URL(string: s)
    }

    /// The primary date to show on the calendar: streaming date if set and past theatrical,
    /// otherwise theatrical date.
    var primaryCalendarDate: Date {
        let today = Calendar.current.startOfDay(for: .now)
        if theatricalReleaseDate != .distantFuture && theatricalReleaseDate >= today {
            return theatricalReleaseDate
        }
        return streamingReleaseDate ?? theatricalReleaseDate
    }
}
