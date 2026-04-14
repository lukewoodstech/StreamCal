import Foundation
import SwiftData
import SwiftUI

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

    var badgeColor: Color {
        switch self {
        case .netflix:       return .red
        case .hulu:          return .green
        case .disneyPlus:    return .blue
        case .max:           return .purple
        case .appleTV:       return .primary
        case .amazonPrime:   return .cyan
        case .peacock:       return .indigo
        case .paramountPlus: return .teal
        case .starz:         return Color(red: 0.1, green: 0.3, blue: 0.7)
        case .mgmPlus:       return .orange
        case .amcPlus:       return Color(red: 0.8, green: 0.1, blue: 0.1)
        case .fx:            return .primary
        case .crunchyroll:   return .orange
        case .discoveryPlus: return .blue
        case .espnPlus:      return .red
        case .britbox:       return Color(red: 0.0, green: 0.35, blue: 0.75)
        case .shudder:       return .purple
        case .fubo:          return Color(red: 0.0, green: 0.6, blue: 0.3)
        case .tubi:          return Color(red: 0.9, green: 0.1, blue: 0.4)
        case .plutoTV:       return .indigo
        case .nbc:           return Color(red: 0.9, green: 0.5, blue: 0.0)
        case .abc:           return .secondary
        case .cbs:           return .blue
        case .fox:           return Color(red: 0.9, green: 0.6, blue: 0.0)
        case .pbs:           return .blue
        case .other:         return .secondary
        }
    }

    var cardBackgroundColor: Color {
        self == .appleTV ? .black : (self == .fx || self == .abc || self == .other ? Color(.systemGray3) : badgeColor)
    }

    var abbreviatedName: String {
        self == .amazonPrime ? "Prime" : rawValue
    }

    var sfSymbol: String {
        switch self {
        case .netflix:       return "play.rectangle.fill"
        case .hulu:          return "play.tv.fill"
        case .disneyPlus:    return "sparkles"
        case .max:           return "film.stack"
        case .appleTV:       return "apple.logo"
        case .amazonPrime:   return "shippingbox.fill"
        case .peacock:       return "bird.fill"
        case .paramountPlus: return "mountain.2.fill"
        case .starz:         return "star.fill"
        case .mgmPlus:       return "theatermasks.fill"
        case .amcPlus:       return "popcorn.fill"
        case .fx:            return "tv.fill"
        case .crunchyroll:   return "tornado"
        case .discoveryPlus: return "globe.americas.fill"
        case .espnPlus:      return "sportscourt.fill"
        case .britbox:       return "flag.fill"
        case .shudder:       return "moon.fill"
        case .fubo:          return "antenna.radiowaves.left.and.right"
        case .tubi:          return "rectangle.on.rectangle"
        case .plutoTV:       return "tv.badge.wifi"
        case .nbc:           return "antenna.radiowaves.left.and.right.slash"
        case .abc:           return "play.circle.fill"
        case .cbs:           return "eye.fill"
        case .fox:           return "bolt.fill"
        case .pbs:           return "book.fill"
        case .other:         return "ellipsis.circle"
        }
    }

    /// Fuzzy-match a TMDB watch provider name (e.g. "Amazon Prime Video") to a StreamingPlatform case.
    static func match(providerName: String) -> StreamingPlatform? {
        let name = providerName.lowercased()
        if name.contains("netflix")                              { return .netflix }
        if name.contains("hulu")                                 { return .hulu }
        if name.contains("disney")                               { return .disneyPlus }
        if name.contains("max") || name.contains("hbo")         { return .max }
        if name.contains("apple")                                { return .appleTV }
        if name.contains("amazon") || name.contains("prime")    { return .amazonPrime }
        if name.contains("peacock")                              { return .peacock }
        if name.contains("paramount") || name.contains("showtime") { return .paramountPlus }
        if name.contains("starz")                                { return .starz }
        if name.contains("mgm")                                  { return .mgmPlus }
        if name.contains("amc")                                  { return .amcPlus }
        if name.contains("crunchyroll")                          { return .crunchyroll }
        if name.contains("discovery")                            { return .discoveryPlus }
        if name.contains("espn")                                 { return .espnPlus }
        if name.contains("britbox")                              { return .britbox }
        if name.contains("shudder")                              { return .shudder }
        if name.contains("fubo")                                 { return .fubo }
        if name.contains("tubi")                                 { return .tubi }
        if name.contains("pluto")                                { return .plutoTV }
        return nil
    }

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

    /// User has marked this show as already seen — used only for AI context, never shown in UI.
    var isSeen: Bool = false

    /// All platforms this show is available on (populated from TMDB networks).
    /// Empty for shows added before multi-platform support — fall back to `platform`.
    var platforms: [String] = []

    /// Streaming service names from TMDB watch/providers (US flatrate). Populated on import and refresh.
    var watchProviderNames: [String] = []

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

    /// Watch providers matched to StreamingPlatform cases for UI display.
    var matchedStreamingPlatforms: [StreamingPlatform] {
        watchProviderNames.compactMap { StreamingPlatform.match(providerName: $0) }
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

    var posterImageURL: URL? {
        guard let s = posterURL else { return nil }
        return URL(string: s)
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
