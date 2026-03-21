import Foundation
import SwiftData

enum StreamingPlatform: String, CaseIterable, Codable, Hashable, Identifiable {
    // Major streaming
    case netflix = "Netflix"
    case hulu = "Hulu"
    case disneyPlus = "Disney+"
    case max = "Max"
    case appleTV = "Apple TV+"
    case amazonPrime = "Prime Video"
    case peacock = "Peacock"
    case paramountPlus = "Paramount+"
    // Premium
    case starz = "Starz"
    case mgmPlus = "MGM+"
    // Niche streaming
    case amcPlus = "AMC+"
    case fx = "FX"
    case crunchyroll = "Crunchyroll"
    case discoveryPlus = "discovery+"
    case espnPlus = "ESPN+"
    case britbox = "BritBox"
    case shudder = "Shudder"
    case fubo = "Fubo"
    case tubi = "Tubi"
    case plutoTV = "Pluto TV"
    // Broadcast
    case nbc = "NBC"
    case abc = "ABC"
    case cbs = "CBS"
    case fox = "Fox"
    case pbs = "PBS"

    case other = "Other"

    var id: String { rawValue }

    var webURL: URL? {
        let str: String
        switch self {
        case .netflix:       str = "https://www.netflix.com"
        case .hulu:          str = "https://www.hulu.com"
        case .disneyPlus:    str = "https://www.disneyplus.com"
        case .max:           str = "https://www.max.com"
        case .appleTV:       str = "https://tv.apple.com"
        case .amazonPrime:   str = "https://www.amazon.com/gp/video/storefront"
        case .peacock:       str = "https://www.peacocktv.com"
        case .paramountPlus: str = "https://www.paramountplus.com"
        case .starz:         str = "https://www.starz.com"
        case .mgmPlus:       str = "https://www.mgmplus.com"
        case .amcPlus:       str = "https://www.amcplus.com"
        case .fx:            str = "https://www.hulu.com"
        case .crunchyroll:   str = "https://www.crunchyroll.com"
        case .discoveryPlus: str = "https://www.discoveryplus.com"
        case .espnPlus:      str = "https://www.espnplus.com"
        case .britbox:       str = "https://www.britbox.com"
        case .shudder:       str = "https://www.shudder.com"
        case .fubo:          str = "https://www.fubo.tv"
        case .tubi:          str = "https://tubitv.com"
        case .plutoTV:       str = "https://pluto.tv"
        case .nbc:           str = "https://www.nbc.com"
        case .abc:           str = "https://abc.com"
        case .cbs:           str = "https://www.cbs.com"
        case .fox:           str = "https://www.fox.com"
        case .pbs:           str = "https://www.pbs.org/watch"
        case .other:         return nil
        }
        return URL(string: str)
    }
}

@Model
final class Show: Identifiable {
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

    /// When false, all notifications for this show are suppressed.
    var notificationsEnabled: Bool = true

    /// All platforms this show is available on (populated from TMDB networks).
    /// Empty for shows added before multi-platform support — fall back to `platform`.
    var platforms: [String] = []

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

    /// The next episode the user should watch: the earliest unwatched aired episode,
    /// or if fully up to date, the next future/TBA episode.
    var nextToWatch: Episode? {
        let unwatched = episodes.filter { !$0.isWatched }
        let sorted = unwatched.sorted {
            if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
            return $0.episodeNumber < $1.episodeNumber
        }
        return sorted.first
    }

    /// The next episode airing today or in the future (not yet watched), or TBA.
    var nextUpcomingEpisode: Episode? {
        let today = Calendar.current.startOfDay(for: .now)
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

    /// Unwatched episodes that aired strictly before today, in watch order.
    var backlogEpisodes: [Episode] {
        let today = Calendar.current.startOfDay(for: .now)
        return episodes
            .filter { !$0.isWatched && $0.airDate < today && $0.airDate != .distantFuture }
            .sorted {
                if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
                return $0.episodeNumber < $1.episodeNumber
            }
    }

    var backlogCount: Int { backlogEpisodes.count }

    var hasWatchBacklog: Bool { backlogCount > 0 }

    /// The most recently watched episode, for "up to date through" display.
    var lastWatchedEpisode: Episode? {
        episodes
            .filter { $0.isWatched }
            .sorted {
                if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber > $1.seasonNumber }
                return $0.episodeNumber > $1.episodeNumber
            }
            .first
    }

    /// True if all episodes have been watched and there's nothing upcoming.
    var isFullyCaughtUp: Bool {
        !episodes.isEmpty && episodes.allSatisfy { $0.isWatched } && nextUpcomingEpisode == nil
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
