import Foundation

// MARK: - TMDB API Response Models

struct TMDBSearchResponse: Decodable, Sendable {
    let results: [TMDBShow]
}

struct TMDBShow: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let firstAirDate: String?
    let voteAverage: Double?

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300\(path)")
    }

    var posterThumbnailURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w92\(path)")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
    }
}

struct TMDBSeasonListResponse: Decodable, Sendable {
    let seasons: [TMDBSeasonSummary]
    let networks: [TMDBNetwork]?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case seasons, networks, status
    }
}

struct TMDBSeasonSummary: Decodable, Sendable {
    let seasonNumber: Int
    let episodeCount: Int

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
    }
}

struct TMDBNetwork: Decodable, Sendable {
    let name: String
}

struct TMDBSeasonResponse: Decodable, Sendable {
    let episodes: [TMDBEpisode]
}

struct TMDBEpisode: Decodable, Sendable {
    let seasonNumber: Int
    let episodeNumber: Int
    let name: String?
    let airDate: String?

    var parsedAirDate: Date? {
        guard let raw = airDate, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw)
    }

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case name
        case airDate = "air_date"
    }
}

// MARK: - TMDB Service

actor TMDBService {

    static let shared = TMDBService()

    private let token = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJlMWQ4OTNiZTA5M2ZiNzk5ODRkZTdhMWViZTkwYjU4ZSIsIm5iZiI6MTc3Mjc1NDMxNS4yMDcsInN1YiI6IjY5YWExNThiZjhiY2NiZDM1NTU0YjI1NiIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.YkPtG1wD5CYcoPSiUywkYKdsGmeeyPiSydodB0xDim0"
    private let baseURL = "https://api.themoviedb.org/3"
    private let session = URLSession.shared

    private func request(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        var components = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        return req
    }

    // MARK: - Search

    func searchShows(query: String) async throws -> [TMDBShow] {
        let req = try request(path: "/search/tv", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "1")
        ])
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return response.results
    }

    // MARK: - Show Details (seasons list + network info)

    func fetchShowDetails(tmdbID: Int) async throws -> TMDBSeasonListResponse {
        let req = try request(path: "/tv/\(tmdbID)")
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(TMDBSeasonListResponse.self, from: data)
    }

    // MARK: - Season Episodes

    func fetchSeason(tmdbID: Int, seasonNumber: Int) async throws -> [TMDBEpisode] {
        let req = try request(path: "/tv/\(tmdbID)/season/\(seasonNumber)")
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TMDBSeasonResponse.self, from: data)
        return response.episodes
    }

    // MARK: - Full Episode Import

    /// Fetches all episodes across all seasons for a show.
    /// Skips season 0 (specials). Returns episodes with valid air dates only.
    func fetchAllEpisodes(tmdbID: Int) async throws -> [TMDBEpisode] {
        let details = try await fetchShowDetails(tmdbID: tmdbID)
        let realSeasons = details.seasons.filter { $0.seasonNumber > 0 }

        var allEpisodes: [TMDBEpisode] = []
        for season in realSeasons {
            let episodes = try await fetchSeason(tmdbID: tmdbID, seasonNumber: season.seasonNumber)
            allEpisodes.append(contentsOf: episodes)
        }
        return allEpisodes
    }
}
