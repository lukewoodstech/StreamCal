import Foundation
import AuthenticationServices
import Combine
import SwiftData
import SwiftUI

// MARK: - Trakt Service

/// Handles Trakt.tv OAuth and watch-history sync.
/// Watch history is synced silently on launch and used only for AI context.
/// The user never needs to interact with watched state in the UI.
@MainActor
final class TraktService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = TraktService()

    // MARK: - Credentials
    // 1. Go to https://trakt.tv/oauth/applications → New Application
    // 2. Name: StreamCal, Redirect URI: streamcal://auth/trakt, check all permissions
    // 3. Paste the Client ID and Secret below
    private let clientID     = "9a2d80ff2e0bed1578495fa788c077926c2de0df406a8097ce28f89cada62429"
    private let clientSecret = "5dd83160df3432f08b976904cf2276e6c0a41517aa767da3ddc7b4ea992de942"
    private let redirectURI  = "streamcal://auth/trakt"

    // MARK: - Published State

    @Published private(set) var isConnected = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedCount = 0

    // MARK: - Token Storage

    @AppStorage("traktAccessToken")  private var accessToken: String = ""
    @AppStorage("traktRefreshToken") private var refreshToken: String = ""

    // Hold a strong reference so ARC doesn't kill the session before it completes
    private var authSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        isConnected = !accessToken.isEmpty
    }

    // MARK: - Connect / Disconnect

    func connect() {
        guard var components = URLComponents(string: "https://trakt.tv/oauth/authorize") else { return }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id",     value: clientID),
            URLQueryItem(name: "redirect_uri",  value: redirectURI)
        ]
        guard let authURL = components.url else { return }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "streamcal"
        ) { [weak self] callbackURL, error in
            guard let self, error == nil, let callbackURL else { return }
            guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else { return }
            Task { await self.exchangeCode(code) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    func disconnect() {
        accessToken = ""
        refreshToken = ""
        isConnected = false
        lastSyncedCount = 0
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .keyWindow ?? ASPresentationAnchor()
        }
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String) async {
        guard let token = try? await requestToken(grantType: "authorization_code", value: code) else { return }
        accessToken = token.accessToken
        refreshToken = token.refreshToken
        isConnected = true
    }

    private func refreshAccessToken() async -> Bool {
        guard !refreshToken.isEmpty,
              let token = try? await requestToken(grantType: "refresh_token", value: refreshToken) else {
            disconnect()
            return false
        }
        accessToken = token.accessToken
        refreshToken = token.refreshToken
        return true
    }

    private func requestToken(grantType: String, value: String) async throws -> TraktTokenResponse {
        var req = URLRequest(url: URL(string: "https://api.trakt.tv/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = [
            "client_id":     clientID,
            "client_secret": clientSecret,
            "redirect_uri":  redirectURI,
            "grant_type":    grantType
        ]
        if grantType == "authorization_code" { body["code"] = value }
        else                                  { body["refresh_token"] = value }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(TraktTokenResponse.self, from: data)
    }

    // MARK: - Sync History

    /// Pulls complete watch history from Trakt and silently sets `isWatched = true`
    /// on matching local episodes and movies. Additive only — never clears watched state.
    func syncHistory(modelContext: ModelContext) async {
        guard isConnected else { return }
        isSyncing = true
        defer { isSyncing = false }

        var count = 0

        // --- Shows ---
        if let watchedShows = await fetchWatched([TraktWatchedShow].self, path: "/sync/watched/shows") {
            let descriptor = FetchDescriptor<Show>()
            if let shows = try? modelContext.fetch(descriptor) {
                var showMap: [Int: Show] = [:]
                for show in shows {
                    if let id = show.tmdbID { showMap[id] = show }
                }

                for watched in watchedShows {
                    guard let tmdbID = watched.show.ids.tmdb,
                          let local = showMap[tmdbID] else { continue }

                    var epMap: [String: Episode] = [:]
                    for ep in local.episodes {
                        epMap["\(ep.seasonNumber)-\(ep.episodeNumber)"] = ep
                    }

                    for season in watched.seasons {
                        for ep in season.episodes {
                            let key = "\(season.number)-\(ep.number)"
                            if let localEp = epMap[key], !localEp.isWatched {
                                localEp.isWatched = true
                                count += 1
                            }
                        }
                    }
                }
            }
        }

        // --- Movies ---
        if let watchedMovies = await fetchWatched([TraktWatchedMovie].self, path: "/sync/watched/movies") {
            let descriptor = FetchDescriptor<Movie>()
            if let movies = try? modelContext.fetch(descriptor) {
                var movieMap: [Int: Movie] = [:]
                for movie in movies {
                    if let id = movie.tmdbID { movieMap[id] = movie }
                }

                for watched in watchedMovies {
                    guard let tmdbID = watched.movie.ids.tmdb,
                          let local = movieMap[tmdbID], !local.isWatched else { continue }
                    local.isWatched = true
                    count += 1
                }
            }
        }

        try? modelContext.save()
        lastSyncedCount = count
    }

    // MARK: - Trakt API

    private func fetchWatched<T: Decodable>(_ type: T.Type, path: String) async -> T? {
        guard let req = makeRequest(path: path) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                guard await refreshAccessToken(), let refreshed = makeRequest(path: path) else { return nil }
                let (data2, _) = try await URLSession.shared.data(for: refreshed)
                return try? JSONDecoder().decode(type, from: data2)
            }
            return try? JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }

    private func makeRequest(path: String) -> URLRequest? {
        guard !accessToken.isEmpty,
              let url = URL(string: "https://api.trakt.tv\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)",  forHTTPHeaderField: "Authorization")
        req.setValue("application/json",       forHTTPHeaderField: "Content-Type")
        req.setValue("2",                      forHTTPHeaderField: "trakt-api-version")
        req.setValue(clientID,                 forHTTPHeaderField: "trakt-api-key")
        return req
    }
}

// MARK: - Response Models

private struct TraktTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct TraktWatchedShow: Decodable {
    let show: Wrapper
    let seasons: [Season]

    struct Wrapper: Decodable { let ids: IDs }
    struct IDs: Decodable { let tmdb: Int? }
    struct Season: Decodable {
        let number: Int
        let episodes: [TraktEpisode]
    }
    struct TraktEpisode: Decodable {
        let number: Int
        let plays: Int
    }
}

private struct TraktWatchedMovie: Decodable {
    let movie: Wrapper
    struct Wrapper: Decodable { let ids: IDs }
    struct IDs: Decodable { let tmdb: Int? }
}
