import Foundation
import SwiftData

// MARK: - Sport Team

@Model
final class SportTeam {
    var name: String
    var sportsDBID: String          // TheSportsDB uses string IDs
    var sport: String               // "American Football", "Basketball", "Soccer"
    var league: String              // "NFL", "NBA", "Premier League"
    var leagueID: String?           // for season-level fetches
    var country: String?
    var badgeURL: String?           // team logo URL
    var dataSource: String = "tsdb" // "tsdb" or "espn"
    var notificationsEnabled: Bool = true
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SportGame.team)
    var games: [SportGame] = []

    init(
        name: String,
        sportsDBID: String,
        sport: String,
        league: String,
        leagueID: String? = nil,
        country: String? = nil,
        badgeURL: String? = nil,
        dataSource: String = "tsdb",
        createdAt: Date = .now
    ) {
        self.name = name
        self.sportsDBID = sportsDBID
        self.sport = sport
        self.league = league
        self.leagueID = leagueID
        self.country = country
        self.badgeURL = badgeURL
        self.dataSource = dataSource
        self.createdAt = createdAt
    }

    var badgeImageURL: URL? {
        guard let s = badgeURL else { return nil }
        return URL(string: s)
    }
}

// MARK: - Sport Game

@Model
final class SportGame {
    var sportsDBEventID: String
    var title: String               // "Manchester City vs Arsenal"
    var homeTeam: String
    var awayTeam: String
    var gameDate: Date              // .distantFuture = TBA; stored as UTC game time
    var venue: String?
    var round: String?              // "Week 28", "Round of 16", "Playoffs"
    var season: String?             // "2025-2026"
    var result: String?             // nil until completed, e.g. "3–1"
    var isCompleted: Bool = false
    var broadcastNetwork: String?   // e.g. "ESPN", "TNT", "NBC" — ESPN teams only
    var createdAt: Date

    var team: SportTeam?

    init(
        sportsDBEventID: String,
        title: String,
        homeTeam: String,
        awayTeam: String,
        gameDate: Date = .distantFuture,
        venue: String? = nil,
        round: String? = nil,
        season: String? = nil,
        result: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date = .now
    ) {
        self.sportsDBEventID = sportsDBEventID
        self.title = title
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.gameDate = gameDate
        self.venue = venue
        self.round = round
        self.season = season
        self.result = result
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    var displayTitle: String { title }

    var formattedGameTime: String {
        guard gameDate != .distantFuture else { return "TBA" }
        return gameDate.formatted(.dateTime.hour().minute())
    }
}
