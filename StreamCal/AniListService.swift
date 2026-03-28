import Foundation

// MARK: - Response Models

struct AniListResult: Identifiable {
    let id: Int
    let titleRomaji: String
    let titleEnglish: String?
    let coverImageURL: String?
    let overview: String?
    let totalEpisodes: Int?
    let status: String
    let nextAiringEpisode: AniListNextAiring?

    var displayTitle: String { titleEnglish ?? titleRomaji }
}

struct AniListNextAiring {
    let episode: Int
    let airingAt: Int   // Unix timestamp
}

struct AniListDetail {
    let id: Int
    let titleRomaji: String
    let titleEnglish: String?
    let coverImageURL: String?
    let overview: String?
    let totalEpisodes: Int?
    let status: String
    let genres: [String]
    /// All episodes that have already aired, with real timestamps
    let airedEpisodes: [(episodeNumber: Int, airDate: Date)]
    /// Next scheduled episode (not yet aired)
    let nextAiringEpisode: AniListNextAiring?
}

// MARK: - AniList Service

actor AniListService {

    static let shared = AniListService()
    private init() {}

    private let endpoint = URL(string: "https://graphql.anilist.co")!
    private let session = URLSession.shared

    // MARK: - Search

    func search(_ query: String) async throws -> [AniListResult] {
        let gql = """
        query SearchAnime($search: String) {
          Page(page: 1, perPage: 20) {
            media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
              id
              title { romaji english }
              coverImage { large }
              description(asHtml: false)
              episodes
              status
              nextAiringEpisode { episode airingAt }
            }
          }
        }
        """
        let json = try await post(query: gql, variables: ["search": query])
        return parseMediaList(from: json)
    }

    // MARK: - Trending

    func fetchTrending() async throws -> [AniListResult] {
        let gql = """
        query TrendingAnime {
          Page(page: 1, perPage: 20) {
            media(type: ANIME, sort: TRENDING_DESC, status_in: [RELEASING, NOT_YET_RELEASED]) {
              id
              title { romaji english }
              coverImage { large }
              description(asHtml: false)
              episodes
              status
              nextAiringEpisode { episode airingAt }
            }
          }
        }
        """
        let json = try await post(query: gql, variables: [:])
        return parseMediaList(from: json)
    }

    // MARK: - Detail

    func fetchDetails(anilistID: Int) async throws -> AniListDetail {
        let gql = """
        query AnimeDetail($id: Int) {
          Media(id: $id, type: ANIME) {
            id
            title { romaji english }
            coverImage { large }
            description(asHtml: false)
            episodes
            status
            genres
            airingSchedule(notYetAired: false, perPage: 50) {
              nodes { episode airingAt }
            }
            nextAiringEpisode { episode airingAt }
          }
        }
        """
        let variables: [String: Any] = ["id": anilistID]
        let json = try await post(query: gql, variables: variables)

        guard let media = json["data"] as? [String: Any],
              let raw = media["Media"] as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return parseDetail(from: raw)
    }

    // MARK: - Private

    private func post(query: String, variables: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = ["query": query, "variables": variables]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }

    private func parseMediaList(from json: [String: Any]) -> [AniListResult] {
        guard let data = json["data"] as? [String: Any],
              let page = data["Page"] as? [String: Any],
              let media = page["media"] as? [[String: Any]] else { return [] }
        return media.compactMap { parseResult(from: $0) }
    }

    private func parseResult(from raw: [String: Any]) -> AniListResult? {
        guard let id = raw["id"] as? Int else { return nil }
        let title = raw["title"] as? [String: Any]
        let romaji = title?["romaji"] as? String ?? "Unknown"
        let english = title?["english"] as? String
        let cover = (raw["coverImage"] as? [String: Any])?["large"] as? String
        let desc = raw["description"] as? String
        let episodes = raw["episodes"] as? Int
        let status = raw["status"] as? String ?? "RELEASING"
        let nextRaw = raw["nextAiringEpisode"] as? [String: Any]
        let next = nextRaw.flatMap { parseNextAiring(from: $0) }
        return AniListResult(id: id, titleRomaji: romaji, titleEnglish: english,
                             coverImageURL: cover, overview: desc, totalEpisodes: episodes,
                             status: status, nextAiringEpisode: next)
    }

    private func parseDetail(from raw: [String: Any]) -> AniListDetail {
        let id = raw["id"] as? Int ?? 0
        let title = raw["title"] as? [String: Any]
        let romaji = title?["romaji"] as? String ?? "Unknown"
        let english = title?["english"] as? String
        let cover = (raw["coverImage"] as? [String: Any])?["large"] as? String
        let desc = raw["description"] as? String
        let episodes = raw["episodes"] as? Int
        let status = raw["status"] as? String ?? "RELEASING"
        let genres = raw["genres"] as? [String] ?? []

        let airingNodes = (raw["airingSchedule"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let aired: [(Int, Date)] = airingNodes.compactMap { node in
            guard let ep = node["episode"] as? Int,
                  let at = node["airingAt"] as? Int else { return nil }
            return (ep, Date(timeIntervalSince1970: Double(at)))
        }

        let nextRaw = raw["nextAiringEpisode"] as? [String: Any]
        let next = nextRaw.flatMap { parseNextAiring(from: $0) }

        return AniListDetail(id: id, titleRomaji: romaji, titleEnglish: english,
                             coverImageURL: cover, overview: desc, totalEpisodes: episodes,
                             status: status, genres: genres,
                             airedEpisodes: aired.map { (episodeNumber: $0.0, airDate: $0.1) },
                             nextAiringEpisode: next)
    }

    private func parseNextAiring(from raw: [String: Any]) -> AniListNextAiring? {
        guard let ep = raw["episode"] as? Int,
              let at = raw["airingAt"] as? Int else { return nil }
        return AniListNextAiring(episode: ep, airingAt: at)
    }
}
