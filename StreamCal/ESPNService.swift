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
        ESPNLeagueConfig(name: "NFL", sport: "football",   league: "nfl",  icon: "football.fill"),
        ESPNLeagueConfig(name: "NBA", sport: "basketball", league: "nba",  icon: "basketball.fill"),
        ESPNLeagueConfig(name: "MLB", sport: "baseball",   league: "mlb",  icon: "baseball.fill"),
        ESPNLeagueConfig(name: "NHL", sport: "hockey",     league: "nhl",  icon: "hockey.puck.fill"),
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

    /// Search all 4 leagues concurrently and filter by name/abbreviation.
    func searchTeams(query: String) async throws -> [ESPNTeam] {
        let lower = query.lowercased()
        async let nfl = fetchTeams(for: ESPNService.leagues[0])
        async let nba = fetchTeams(for: ESPNService.leagues[1])
        async let mlb = fetchTeams(for: ESPNService.leagues[2])
        async let nhl = fetchTeams(for: ESPNService.leagues[3])

        let nflTeams = (try? await nfl) ?? []
        let nbaTeams = (try? await nba) ?? []
        let mlbTeams = (try? await mlb) ?? []
        let nhlTeams = (try? await nhl) ?? []
        let all = nflTeams + nbaTeams + mlbTeams + nhlTeams

        return all.filter {
            $0.displayName.lowercased().contains(lower) ||
            $0.abbreviation.lowercased() == lower
        }
    }

    // MARK: - Schedule

    /// Fetch full team schedule. ESPN ID stored in team.sportsDBID, path in team.leagueID.
    func fetchSchedule(espnTeamID: String, sport: String, leaguePath: String) async throws -> [ESPNEvent] {
        guard let url = URL(string: "\(baseURL)/\(sport)/\(leaguePath)/teams/\(espnTeamID)/schedule") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(ESPNScheduleResponse.self, from: data)
        return response.events ?? []
    }
}

// MARK: - In-Memory Cache

private actor ESPNTeamCache {
    private var store: [String: [ESPNTeam]] = [:]
    func teams(for league: String) -> [ESPNTeam]? { store[league] }
    func set(_ teams: [ESPNTeam], for league: String) { store[league] = teams }
}
