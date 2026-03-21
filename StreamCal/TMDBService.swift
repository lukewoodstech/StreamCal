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
        formatter.timeZone = .current
        guard let date = formatter.date(from: raw) else { return nil }
        // Normalise to midnight local time so date comparisons are always
        // against the same granularity as Calendar.current.startOfDay(for:)
        return Calendar.current.startOfDay(for: date)
    }

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case name
        case airDate = "air_date"
    }
}

// MARK: - TMDB Movie Response Models

struct TMDBMovieSearchResponse: Decodable, Sendable {
    let results: [TMDBMovie]
}

struct TMDBMovie: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let releaseDate: String?        // primary theatrical, "yyyy-MM-dd"
    let voteAverage: Double?
    let status: String?
    let tagline: String?
    let genres: [TMDBMovieGenre]?
    let releaseDates: TMDBReleaseDatesWrapper?   // present when append_to_response=release_dates

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300\(path)")
    }

    var posterThumbnailURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w92\(path)")
    }

    var parsedReleaseDate: Date? { parseDate(releaseDate) }

    /// US theatrical release date (type 3) from the appended release_dates.
    /// Falls back to the root `release_date` field.
    func usTheatricalDate() -> Date? {
        let fromReleaseDates = releaseDates?.results
            .first(where: { $0.iso31661 == "US" })?
            .releaseDates
            .filter { $0.type == 3 }
            .compactMap { parseDate($0.releaseDate) }
            .min()
        return fromReleaseDates ?? parsedReleaseDate
    }

    /// US digital/streaming release date (type 4).
    func usStreamingDate() -> Date? {
        releaseDates?.results
            .first(where: { $0.iso31661 == "US" })?
            .releaseDates
            .filter { $0.type == 4 }
            .compactMap { parseDate($0.releaseDate) }
            .min()
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        guard let date = formatter.date(from: raw) else { return nil }
        return Calendar.current.startOfDay(for: date)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, overview, status, tagline, genres
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case releaseDates = "release_dates"
    }
}

struct TMDBMovieGenre: Decodable, Sendable {
    let id: Int
    let name: String
}

struct TMDBReleaseDatesWrapper: Decodable, Sendable {
    let results: [TMDBCountryReleases]
}

struct TMDBCountryReleases: Decodable, Sendable {
    let iso31661: String
    let releaseDates: [TMDBReleaseDate]
    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}

struct TMDBReleaseDate: Decodable, Sendable {
    let releaseDate: String     // ISO 8601
    let type: Int               // 3 = theatrical, 4 = digital
    enum CodingKeys: String, CodingKey {
        case releaseDate = "release_date"
        case type
    }
}

// MARK: - TMDB Service

final class TMDBService: Sendable {

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

    // MARK: - Movie Search

    func searchMovies(query: String) async throws -> [TMDBMovie] {
        let req = try request(path: "/search/movie", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "1")
        ])
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TMDBMovieSearchResponse.self, from: data)
        return response.results
    }

    // MARK: - Movie Details (with release dates appended)

    /// Single call that returns movie detail + US release dates.
    /// Use `movie.usTheatricalDate()` and `movie.usStreamingDate()` on the result.
    func fetchMovieDetails(tmdbID: Int) async throws -> TMDBMovie {
        let req = try request(path: "/movie/\(tmdbID)", queryItems: [
            URLQueryItem(name: "append_to_response", value: "release_dates")
        ])
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(TMDBMovie.self, from: data)
    }

    // MARK: - Upcoming Movies

    func fetchUpcomingMovies() async throws -> [TMDBMovie] {
        let req = try request(path: "/movie/upcoming", queryItems: [
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "page", value: "1")
        ])
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TMDBMovieSearchResponse.self, from: data)
        return response.results
    }
}
