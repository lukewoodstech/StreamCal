import Foundation

// MARK: - League Config

struct ESPNLeagueConfig: Sendable {
    let name: String        // "NFL", "NBA", "MLB", "NHL"
    let sport: String       // "football", "basketball", "baseball", "hockey"
    let league: String      // "nfl", "nba", "mlb", "nhl"
    let icon: String        // SF Symbol
    var leaguePath: String { "\(sport)/\(league)" }  // "football/nfl"
}

// MARK: - ESPN Response Models

private struct ESPNTeamsResponse: Decodable {
    let sports: [ESPNSportData]
}

private struct ESPNSportData: Decodable {
    let leagues: [ESPNLeagueData]
}

private struct ESPNLeagueData: Decodable {
    let teams: [ESPNTeamWrapper]
}

private struct ESPNTeamWrapper: Decodable {
    let team: ESPNTeamPayload
}

private struct ESPNTeamPayload: Decodable {
    let id: String
    let displayName: String
    let abbreviation: String?
    let logos: [ESPNLogo]?
}

private struct ESPNLogo: Decodable {
    let href: String
    let rel: [String]
}

struct ESPNScheduleResponse: Decodable {
    let events: [ESPNEvent]?
}

struct ESPNEvent: Decodable, Identifiable {
    let id: String
    let name: String
    let date: String        // ISO8601 UTC e.g. "2025-09-07T17:00Z"
    let competitions: [ESPNCompetition]

    var parsedDate: Date? {
        // ESPN omits seconds in some responses ("2025-09-07T17:00Z"), which the
        // default ISO8601DateFormatter won't parse. Try with and without seconds.
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: date) { return d }
        // Append ":00" before the Z and retry
        let withSeconds = date.replacingOccurrences(of: "Z", with: ":00Z")
        return iso.date(from: withSeconds)
    }
}

struct ESPNCompetition: Decodable {
    let competitors: [ESPNCompetitor]
    let venue: ESPNVenue?
    let status: ESPNStatus?
    let broadcasts: [ESPNBroadcast]?
}

struct ESPNBroadcast: Decodable {
    // market can be a String or an object depending on ESPN endpoint — skip it
    let names: [String]?
}

struct ESPNCompetitor: Decodable {
    let homeAway: String    // "home" | "away"
    let team: ESPNTeamRef
    let score: ESPNScore?
}

struct ESPNTeamRef: Decodable {
    let displayName: String
}

struct ESPNScore: Decodable {
    let value: Double?
}

struct ESPNVenue: Decodable {
    let fullName: String?
}

struct ESPNStatus: Decodable {
    let type: ESPNStatusType?
}

struct ESPNStatusType: Decodable {
    let completed: Bool?
}

// MARK: - Public Team Model

struct ESPNTeam: Identifiable, Sendable {
    let id: String
    let displayName: String
    let abbreviation: String
    let league: String          // "NFL", "NBA", "MLB", "NHL"
    let sport: String           // "football", "basketball", "baseball", "hockey"
    let leaguePath: String      // "nfl", "nba", "mlb", "nhl"
    let logoURL: URL?
}

// MARK: - ESPN Service

final class ESPNService: Sendable {

    static let shared = ESPNService()

    static let leagues: [ESPNLeagueConfig] = [
        // North American Pro
        ESPNLeagueConfig(name: "NFL",              sport: "football",    league: "nfl",                      icon: "football.fill"),
        ESPNLeagueConfig(name: "NBA",              sport: "basketball",  league: "nba",                      icon: "basketball.fill"),
        ESPNLeagueConfig(name: "WNBA",             sport: "basketball",  league: "wnba",                     icon: "basketball.fill"),
        ESPNLeagueConfig(name: "MLB",              sport: "baseball",    league: "mlb",                      icon: "baseball.fill"),
        ESPNLeagueConfig(name: "NHL",              sport: "hockey",      league: "nhl",                      icon: "hockey.puck.fill"),
        ESPNLeagueConfig(name: "MLS",              sport: "soccer",      league: "usa.1",                    icon: "soccerball"),
        // College
        ESPNLeagueConfig(name: "NCAA Football",    sport: "football",    league: "college-football",          icon: "football.fill"),
        ESPNLeagueConfig(name: "NCAA Basketball",  sport: "basketball",  league: "mens-college-basketball",   icon: "basketball.fill"),
        // International Soccer
        ESPNLeagueConfig(name: "Champions League", sport: "soccer",      league: "uefa.champions",            icon: "soccerball"),
        ESPNLeagueConfig(name: "La Liga",          sport: "soccer",      league: "esp.1",                    icon: "soccerball"),
        ESPNLeagueConfig(name: "Bundesliga",       sport: "soccer",      league: "ger.1",                    icon: "soccerball"),
        ESPNLeagueConfig(name: "Serie A",          sport: "soccer",      league: "ita.1",                    icon: "soccerball"),
        // Motorsport
        ESPNLeagueConfig(name: "F1",               sport: "racing",      league: "f1",                       icon: "flag.checkered.2.crossed"),
        ESPNLeagueConfig(name: "NASCAR Cup",       sport: "racing",      league: "nascar-cup",               icon: "flag.checkered.2.crossed"),
    ]

    private let baseURL = "https://site.api.espn.com/apis/site/v2/sports"
    private let session = URLSession.shared
    private let cache = ESPNTeamCache()

    // MARK: - Teams

    func fetchTeams(for config: ESPNLeagueConfig) async throws -> [ESPNTeam] {
        if let cached = await cache.teams(for: config.league) { return cached }

        guard let url = URL(string: "\(baseURL)/\(config.sport)/\(config.league)/teams") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(ESPNTeamsResponse.self, from: data)

        let teams = response.sports.first?.leagues.first?.teams.map { wrapper -> ESPNTeam in
            let t = wrapper.team
            let logoHref = t.logos?.first(where: { $0.rel.contains("default") })?.href
                        ?? t.logos?.first?.href
            return ESPNTeam(
                id: t.id,
                displayName: t.displayName,
                abbreviation: t.abbreviation ?? "",
                league: config.name,
                sport: config.sport,
                leaguePath: config.league,
                logoURL: logoHref.flatMap { URL(string: $0) }
            )
        } ?? []

        await cache.set(teams, for: config.league)
        return teams
    }

    /// Search all leagues concurrently and filter by name/abbreviation.
    func searchTeams(query: String) async throws -> [ESPNTeam] {
        let lower = query.lowercased()
        let allTeams: [ESPNTeam] = await withTaskGroup(of: [ESPNTeam].self) { group in
            for config in ESPNService.leagues {
                group.addTask { (try? await self.fetchTeams(for: config)) ?? [] }
            }
            var result: [ESPNTeam] = []
            for await teams in group { result.append(contentsOf: teams) }
            return result
        }
        return allTeams.filter {
            $0.displayName.lowercased().contains(lower) ||
            $0.abbreviation.lowercased() == lower
        }
    }

    // MARK: - Schedule

    /// Fetch full team schedule. ESPN ID stored in team.sportsDBID, path in team.leagueID.
    /// Fetches regular season (seasontype=2) + playoffs (seasontype=3) and merges them.
    func fetchSchedule(espnTeamID: String, sport: String, leaguePath: String) async throws -> [ESPNEvent] {
        let base = "\(baseURL)/\(sport)/\(leaguePath)/teams/\(espnTeamID)/schedule"
        var all: [ESPNEvent] = []
        for seasontype in [2, 3] {
            guard let url = URL(string: "\(base)?seasontype=\(seasontype)") else { continue }
            if let (data, _) = try? await session.data(from: url),
               let response = try? JSONDecoder().decode(ESPNScheduleResponse.self, from: data) {
                all += response.events ?? []
            }
        }
        return all
    }
}

// MARK: - In-Memory Cache

private actor ESPNTeamCache {
    private var store: [String: [ESPNTeam]] = [:]
    func teams(for league: String) -> [ESPNTeam]? { store[league] }
    func set(_ teams: [ESPNTeam], for league: String) { store[league] = teams }
}
