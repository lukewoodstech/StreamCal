import Foundation

/// Calls the StreamCal Cloudflare Worker, which holds the API key server-side
/// and verifies the caller's Pro entitlement via RevenueCat before forwarding to Claude.
/// All methods silently return nil on failure — callers fall back to non-AI content.
struct ClaudeService {

    // MARK: - Configuration

    /// The Cloudflare Worker URL. Set this after deploying your worker.
    /// Deploy at: https://dash.cloudflare.com → Workers & Pages → Create Worker
    private static let workerURL = "https://streamcal.YOUR_SUBDOMAIN.workers.dev/ai"

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
        request.timeoutInterval = 20

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
