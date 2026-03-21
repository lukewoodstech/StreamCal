import Foundation

// MARK: - TheSportsDB Response Models

struct SDBTeamSearchResponse: Decodable, Sendable {
    let teams: [SDBTeam]?   // nil when no results (API quirk — returns null not [])
}

struct SDBTeam: Decodable, Identifiable, Sendable {
    let idTeam: String
    let strTeam: String
    let strSport: String
    let strLeague: String?
    let idLeague: String?
    let strCountry: String?
    let strTeamBadge: String?

    var id: String { idTeam }
}

struct SDBEventsResponse: Decodable, Sendable {
    let events: [SDBEvent]?  // nil when no upcoming events
}

struct SDBEvent: Decodable, Identifiable, Sendable {
    let idEvent: String
    let strEvent: String
    let strHomeTeam: String?
    let strAwayTeam: String?
    let dateEvent: String?      // "2026-04-05"
    let strTime: String?        // "15:00:00" UTC (may be absent)
    let strVenue: String?
    let strRound: String?
    let strSeason: String?
    let intHomeScore: String?   // non-null = completed
    let intAwayScore: String?

    var id: String { idEvent }

    var isCompleted: Bool { intHomeScore != nil && intAwayScore != nil }

    var result: String? {
        guard let h = intHomeScore, let a = intAwayScore,
              !h.isEmpty, !a.isEmpty else { return nil }
        return "\(h)–\(a)"
    }

    var parsedGameDate: Date? {
        guard let dateStr = dateEvent, !dateStr.isEmpty else { return nil }
        if let timeStr = strTime, !timeStr.isEmpty, timeStr != "00:00:00" {
            // Combine date + time as UTC
            let combined = "\(dateStr)T\(timeStr)+00:00"
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withTimeZone]
            if let date = iso.date(from: combined) { return date }
        }
        // Date-only fallback: midnight local
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.date(from: dateStr).map { Calendar.current.startOfDay(for: $0) }
    }
}

// MARK: - TheSportsDB Service

/// Wraps TheSportsDB free-tier API (key "3", no auth header required).
/// Rate limit: ~1 req/sec on free tier — callers should add delays between
/// sequential fetches in bulk operations.
final class TheSportsDBService: Sendable {

    static let shared = TheSportsDBService()

    private let baseURL = "https://www.thesportsdb.com/api/v1/json/3"
    private let session = URLSession.shared

    private func request(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        var components = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw URLError(.badURL) }
        return URLRequest(url: url)
    }

    // MARK: - Search

    func searchTeams(query: String) async throws -> [SDBTeam] {
        let req = try request(path: "/searchteams.php", queryItems: [
            URLQueryItem(name: "t", value: query)
        ])
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(SDBTeamSearchResponse.self, from: data)
        return response.teams ?? []
    }

    // MARK: - Events

    /// Next 25 upcoming events for a team (lightweight — used on every launch).
    func fetchNextEvents(teamID: String) async throws -> [SDBEvent] {
        let req = try request(path: "/eventsnext.php", queryItems: [
            URLQueryItem(name: "id", value: teamID)
        ])
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(SDBEventsResponse.self, from: data)
        return response.events ?? []
    }

    /// Full season schedule for a league (used on initial team add + periodic refresh).
    func fetchSeasonEvents(leagueID: String, season: String) async throws -> [SDBEvent] {
        let req = try request(path: "/eventsseason.php", queryItems: [
            URLQueryItem(name: "id", value: leagueID),
            URLQueryItem(name: "s", value: season)
        ])
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(SDBEventsResponse.self, from: data)
        return response.events ?? []
    }
}
