import Foundation

/// Thin HTTP wrapper for the Anthropic Messages API.
/// The API key is read from UserDefaults (stored via @AppStorage in Settings).
/// All methods silently return nil on failure — callers fall back to non-AI content.
struct ClaudeService {

    private static let model = "claude-haiku-4-5-20251001"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Public API

    /// Generate a 2-3 sentence weekly preview for a notification body.
    /// Returns nil if no key is configured or the call fails.
    static func generateWeeklySummary(
        upcoming: [(title: String, date: Date, type: String)]
    ) async -> String? {
        guard !upcoming.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let list = upcoming.prefix(8).map { "\($0.title) (\(formatter.string(from: $0.date)), \($0.type))" }
            .joined(separator: "; ")

        let prompt = """
        You are StreamCal, a personal entertainment tracker. The user has these upcoming this week: \(list).
        Write a 2-3 sentence friendly preview of their week. Be warm, conversational, and specific.
        Keep it under 180 characters total so it fits in a notification.
        """
        return try? await call(prompt: prompt)
    }

    /// Generate a personalized "what to watch tonight" recommendation.
    /// Returns nil if no key is configured or the call fails.
    static func generateWatchRecommendation(
        backlog: [(showTitle: String, count: Int)],
        upcoming: [(showTitle: String, daysUntil: Int)],
        watchedCount: Int
    ) async -> String? {
        var context = ""
        if !backlog.isEmpty {
            let backlogStr = backlog.prefix(5).map { "\($0.showTitle) (\($0.count) eps behind)" }.joined(separator: ", ")
            context += "Backlog: \(backlogStr). "
        }
        if !upcoming.isEmpty {
            let upcomingStr = upcoming.prefix(5).map { "\($0.showTitle) in \($0.daysUntil)d" }.joined(separator: ", ")
            context += "Coming up: \(upcomingStr). "
        }
        context += "Total watched: \(watchedCount) episodes."

        let prompt = """
        You are StreamCal, a friendly personal entertainment tracker. \(context)
        Based on this, recommend what the user should watch tonight in 2-4 sentences.
        Be specific, warm, and give a concrete recommendation. Mention show names and episode context.
        """
        return try? await call(prompt: prompt)
    }

    // MARK: - Private

    private static func call(prompt: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ClaudeError.noAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClaudeError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw ClaudeError.parseError
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var apiKey: String? {
        let key = UserDefaults.standard.string(forKey: "claudeAPIKey") ?? ""
        return key.isEmpty ? nil : key
    }
}

// MARK: - Errors

enum ClaudeError: Error {
    case noAPIKey
    case httpError(Int)
    case parseError
}
