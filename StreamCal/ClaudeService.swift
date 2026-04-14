import Foundation

// MARK: - Library Context

/// Snapshot of the user's library, serialized into a system prompt for Claude.
struct StreamCalContext {
    let shows: [Show]
    let movies: [Movie]
    let teams: [SportTeam]
    let preferredPlatforms: [String]
    let today: Date

    func systemPrompt() -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        var lines: [String] = []

        lines.append("Today is \(df.string(from: today)).")
        lines.append("")

        if !preferredPlatforms.isEmpty {
            lines.append("User's preferred streaming platforms: \(preferredPlatforms.joined(separator: ", "))")
            lines.append("")
        }

        let activeShows = shows.filter { !$0.isArchived }.prefix(20)
        if !activeShows.isEmpty {
            lines.append("SHOWS IN LIBRARY:")
            for show in activeShows {
                var entry = "- \(show.title)"
                let providers = show.watchProviderNames.prefix(2)
                if !providers.isEmpty { entry += " (\(providers.joined(separator: ", ")))" }
                if let status = show.showStatus { entry += " — \(status)" }
                // Watch progress from Trakt sync
                let watchedCount = show.episodes.filter { $0.isWatched }.count
                let totalCount   = show.episodes.count
                if watchedCount > 0 && totalCount > 0 {
                    if watchedCount == totalCount {
                        entry += ", fully watched"
                    } else if let last = show.lastWatchedEpisode {
                        let code = "S\(String(format: "%02d", last.seasonNumber))E\(String(format: "%02d", last.episodeNumber))"
                        entry += ", watched through \(code)"
                    }
                }
                if let next = show.nextUpcomingEpisode {
                    let code = "S\(String(format: "%02d", next.seasonNumber))E\(String(format: "%02d", next.episodeNumber))"
                    if next.airDate == .distantFuture {
                        entry += ", next: \(code) TBA"
                    } else {
                        entry += ", next: \(code) on \(df.string(from: next.airDate))"
                    }
                }
                lines.append(entry)
            }
            lines.append("")
        }

        let activeMovies = movies.filter { !$0.isArchived }.prefix(15)
        if !activeMovies.isEmpty {
            lines.append("MOVIES IN LIBRARY:")
            for movie in activeMovies {
                var entry = "- \(movie.title)"
                if !movie.genres.isEmpty { entry += " (\(movie.genres.prefix(2).joined(separator: ", ")))" }
                switch movie.releaseStatus {
                case .announced:  entry += " — Announced"
                case .comingSoon:
                    if movie.theatricalReleaseDate != .distantFuture {
                        entry += " — Coming Soon, \(df.string(from: movie.theatricalReleaseDate)) (theaters)"
                    } else {
                        entry += " — Coming Soon, TBA"
                    }
                case .released:   entry += " — In Theaters since \(df.string(from: movie.theatricalReleaseDate))"
                case .watched:
                    entry += " — Already watched"
                case .streaming:
                    let providers = movie.watchProviderNames.prefix(2)
                    if !providers.isEmpty {
                        entry += " — Streaming on \(providers.joined(separator: ", "))"
                    } else {
                        entry += " — Streaming Now"
                    }
                }
                lines.append(entry)
            }
            lines.append("")
        }

        if !teams.isEmpty {
            lines.append("SPORTS TEAMS:")
            for team in teams.prefix(10) {
                var entry = "- \(team.name) (\(team.league))"
                let nextGame = team.games
                    .filter { !$0.isCompleted && $0.gameDate > today && $0.gameDate != .distantFuture }
                    .sorted { $0.gameDate < $1.gameDate }
                    .first
                if let game = nextGame {
                    let opponent = game.homeTeam == team.name ? game.awayTeam : game.homeTeam
                    entry += " — next game \(df.string(from: game.gameDate)) vs \(opponent)"
                }
                lines.append(entry)
            }
            lines.append("")
        }

        let seenShows = shows.filter { $0.isSeen }.prefix(15)
        if !seenShows.isEmpty {
            lines.append("SHOWS USER HAS ALREADY SEEN (don't recommend these unless asked):")
            for show in seenShows { lines.append("- \(show.title)") }
            lines.append("")
        }

        let seenMovies = movies.filter { $0.isSeen }.prefix(10)
        if !seenMovies.isEmpty {
            lines.append("MOVIES USER HAS ALREADY SEEN (don't recommend these unless asked):")
            for movie in seenMovies { lines.append("- \(movie.title)") }
            lines.append("")
        }

        lines.append("""
You are StreamCal, a personal entertainment assistant with broad knowledge of TV, movies, anime, and pop culture.

TWO MODES:
1. SCHEDULE (what's airing, what's on tonight, this week, coming up) → use only the library data above. Never invent episode numbers or dates.
2. DISCOVERY (best shows, recommendations, what to watch, what's trending) → use YOUR full knowledge. Do not limit yourself to the library. Recommend real shows/movies you know about.

CRITICAL: Your entire response must be a single raw JSON object. Do NOT wrap in ```json or any code fences. Do NOT include any text before or after the JSON. Start your response with { and end with }.
{"summary":"≤100 chars or null","sections":[{"type":"live_now|airing_tonight|coming_next|recommendations|answer","heading":"Heading","items":[{"title":"Title","detail":"≤35 chars e.g. S02E14 · Max","badge":"≤10 chars","badgeStyle":"live|today|soon|ai|info","isInLibrary":true}]}]}

RULES:
- Omit any section with zero items.
- badge/badgeStyle: omit both if unknown. live=red pulse, today=orange, soon=blue, ai=purple, info=gray.
- detail: omit platform if unknown.
- For DISCOVERY questions: always return 4-6 real recommendations with isInLibrary=false. Never say "I don't have data."
- Never recommend titles marked as already seen.
- Max 6 items total across all sections. Be concise.
- summary: one sentence max, or null.
""")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Claude Service

/// Calls the StreamCal Cloudflare Worker, which holds the API key server-side
/// and verifies the caller's Pro entitlement via RevenueCat before forwarding to Claude.
/// All methods silently return nil on failure — callers fall back to non-AI content.
struct ClaudeService {

    // MARK: - Configuration

    /// The Cloudflare Worker URL. Set this after deploying your worker.
    /// Deploy at: https://dash.cloudflare.com → Workers & Pages → Create Worker
    private static let workerURL = "https://streamcal-ai.lukewoodstech.workers.dev/ai"

    // MARK: - Public API

    /// Generate a 2-3 sentence weekly preview for a notification body.
    static func generateWeeklySummary(
        upcoming: [(title: String, date: Date, type: String)]
    ) async -> String? {
        guard !upcoming.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let list = upcoming.prefix(8)
            .map { "\($0.title) (\(formatter.string(from: $0.date)), \($0.type))" }
            .joined(separator: "; ")

        let prompt = """
        You are StreamCal, a personal entertainment tracker. The user has these upcoming this week: \(list).
        Write a 2-3 sentence friendly preview of their week. Be warm, conversational, and specific.
        Keep it under 180 characters total so it fits in a notification.
        """
        return try? await call(prompt: prompt)
    }

    /// Generate a personalized "what to watch tonight" recommendation.
    static func generateWatchRecommendation(
        backlog: [(showTitle: String, count: Int)],
        upcoming: [(showTitle: String, daysUntil: Int)],
        watchedCount: Int
    ) async -> String? {
        var context = ""
        if !backlog.isEmpty {
            context += "Backlog: " + backlog.prefix(5).map { "\($0.showTitle) (\($0.count) eps behind)" }.joined(separator: ", ") + ". "
        }
        if !upcoming.isEmpty {
            context += "Coming up: " + upcoming.prefix(5).map { "\($0.showTitle) in \($0.daysUntil)d" }.joined(separator: ", ") + ". "
        }
        context += "Total watched: \(watchedCount) episodes."

        let prompt = """
        You are StreamCal, a friendly personal entertainment tracker. \(context)
        Based on this, recommend what the user should watch tonight in 2-4 sentences.
        Be specific, warm, and give a concrete recommendation. Mention show names and episode context.
        """
        return try? await call(prompt: prompt)
    }

    /// Answer a natural language question using the user's library as context.
    static func ask(question: String, context: StreamCalContext) async -> String? {
        let prompt = context.systemPrompt() + "\n\nUser: \(question)"
        return try? await call(prompt: prompt)
    }

    /// Generate a 2-sentence daily brief for what's on today.
    static func generateDailyBrief(items: [String]) async -> String? {
        guard !items.isEmpty else { return nil }
        let prompt = """
        You are StreamCal, a friendly personal entertainment tracker. Today's schedule: \(items.joined(separator: "; ")).
        Write exactly 2 casual sentences previewing the user's day. Be specific, warm, and mention names.
        No quotes. Under 200 characters total.
        """
        return try? await call(prompt: prompt)
    }

    // MARK: - Private

    private static func call(prompt: String) async throws -> String {
        let customerID = await MainActor.run { PurchaseService.shared.customerID }

        guard let url = URL(string: workerURL) else {
            throw AIError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let body: [String: String] = ["prompt": prompt, "customerID": customerID]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw AIError.parseError
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum AIError: Error {
    case badURL
    case notPro
    case httpError(Int)
    case parseError
}
