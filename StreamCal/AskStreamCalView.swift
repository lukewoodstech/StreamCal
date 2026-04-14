import SwiftUI
import SwiftData

// MARK: - Structured Response Models

struct StreamCalResponse: Decodable {
    let summary: String?
    let sections: [StreamCalSection]
}

struct StreamCalSection: Decodable, Identifiable {
    var id: String { type + heading }
    let type: String    // "live_now" | "airing_tonight" | "coming_next" | "recommendations" | "answer"
    let heading: String
    let items: [StreamCalItem]
}

struct StreamCalItem: Decodable, Identifiable {
    var id: String { title }
    let title: String
    let detail: String?
    let badge: String?
    let badgeStyle: String?   // "live" | "today" | "soon" | "ai" | "info"
    let isInLibrary: Bool?
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String                              // summary text (or full text for fallback)
    var structuredResponse: StreamCalResponse?    // non-nil when JSON parse succeeds

    enum Role { case user, assistant }
}

// MARK: - Library Match Result

struct LibraryMatches {
    var shows: [Show] = []
    var movies: [Movie] = []
    var teams: [SportTeam] = []

    var isEmpty: Bool { shows.isEmpty && movies.isEmpty && teams.isEmpty }

    static func find(in text: String, shows: [Show], movies: [Movie], teams: [SportTeam]) -> LibraryMatches {
        let lower = text.lowercased()
        var result = LibraryMatches()
        // Require at least 4 chars to avoid false matches on short words
        result.shows = shows.filter { $0.title.count >= 4 && lower.contains($0.title.lowercased()) }
        result.movies = movies.filter { $0.title.count >= 4 && lower.contains($0.title.lowercased()) }
        result.teams = teams.filter { $0.name.count >= 4 && lower.contains($0.name.lowercased()) }
        return result
    }
}

// MARK: - Ask StreamCal View

struct AskStreamCalView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseService: PurchaseService

    @Query(sort: \Show.title) private var shows: [Show]
    @Query(sort: \Movie.title) private var movies: [Movie]
    @Query(sort: \SportTeam.name) private var teams: [SportTeam]
    @Query(sort: \AnimeShow.titleRomaji) private var animeShows: [AnimeShow]

    @AppStorage("preferredPlatforms") private var preferredPlatformsRaw: String = ""

    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading: Bool = false
    @State private var showingPaywall = false
    @FocusState private var inputFocused: Bool

    // Typewriter animation
    @State private var typingMessageID: UUID? = nil
    @State private var typingText: String = ""
    @State private var typewriterTask: Task<Void, Never>? = nil

    // Entrance animation
    @State private var visibleMessageIDs: Set<UUID> = []

    // Send button feedback
    @State private var sendButtonScale: CGFloat = 1.0

    // Discovery cards keyed by message ID
    @State private var discoveryResultsByMessage: [UUID: [DiscoveryResult]] = [:]
    @State private var addedFromDiscovery: Set<Int> = []  // tmdbIDs added this session
    @State private var addingTmdbID: Int? = nil           // spinner state

    @Environment(\.modelContext) private var modelContext

    private var preferredPlatforms: [String] {
        preferredPlatformsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    private let librarySuggestions = [
        "What's airing tonight?",
        "What do I have coming up this week?",
        "Do I have a backlog to catch up on?"
    ]

    private var discoverySuggestions: [String] {
        var chips = [
            "Recommend something I've never seen",
            "What's trending right now?",
            "What movies are worth watching this month?"
        ]
        if !animeShows.isEmpty {
            chips.append("Recommend a new anime")
        } else {
            chips.append("What are the best new shows of 2025?")
        }
        return chips
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !purchaseService.isPro {
                    lockedState
                } else {
                    chatArea
                    inputBar
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ask StreamCal")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPaywall) {
                AppPaywallView().environmentObject(purchaseService)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                if purchaseService.isPro && !messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { messages = [] }
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        suggestionsView
                            .padding(.top, 24)
                    }
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if isLoading {
                        typingIndicator
                            .id("loading")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .onChange(of: messages.count) {
                withAnimation {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isLoading) {
                if isLoading {
                    withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - AI Avatar

    private var aiAvatar: some View {
        ZStack {
            LinearGradient(
                colors: [DS.Color.ai, DS.Color.ai.opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .shadow(color: DS.Color.ai.opacity(0.35), radius: 6, y: 2)
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        let isVisible = visibleMessageIDs.contains(message.id)
        let isTyping = message.id == typingMessageID
        let isStructured = message.structuredResponse != nil && !isTyping

        VStack(alignment: .leading, spacing: 10) {
            // ── Row: avatar + text bubble ──────────────────────────────
            HStack(alignment: .bottom, spacing: 10) {
                if message.role == .user { Spacer(minLength: 56) }
                if message.role == .assistant { aiAvatar }

                let isRetry = message.text == "__retry__"
                let showBubble = message.role == .user || isTyping || !message.text.isEmpty
                if isRetry && !isTyping {
                    // Retry state — clean error with a tap-to-retry affordance
                    retryBubble(lastUserMessage: messages.last(where: { $0.role == .user })?.text ?? "")
                } else if showBubble {
                    Group {
                        if isTyping {
                            Text(typingText)
                        } else if message.role == .assistant {
                            let attributed = (try? AttributedString(
                                markdown: message.text,
                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                            )) ?? AttributedString(message.text)
                            Text(attributed)
                        } else {
                            Text(message.text)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        message.role == .user
                            ? LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(.secondarySystemGroupedBackground),
                                                       Color(.secondarySystemGroupedBackground)],
                                             startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedCornerShape(
                        radius: DS.Radius.lg,
                        corners: message.role == .user
                            ? [.topLeft, .topRight, .bottomLeft]
                            : [.topLeft, .topRight, .bottomRight]
                    ))
                    .overlay(
                        message.role == .assistant
                        ? RoundedCornerShape(radius: DS.Radius.lg, corners: [.topLeft, .topRight, .bottomRight])
                            .stroke(DS.Color.ai.opacity(0.12), lineWidth: 1)
                        : nil
                    )
                }

                if message.role == .assistant { Spacer(minLength: 56) }
            }

            // ── Structured section cards (after typewriter) ────────────
            if let structured = message.structuredResponse, isStructured {
                StructuredResponseView(response: structured)
                    .padding(.leading, 38)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // ── Discovery + library cards (after typewriter) ───────────
            if message.role == .assistant && !isTyping {
                if let discoveries = discoveryResultsByMessage[message.id], !discoveries.isEmpty {
                    DiscoveryResultsRow(
                        results: discoveries,
                        addedIDs: addedFromDiscovery,
                        addingID: addingTmdbID
                    ) { result in Task { await addDiscoveryItem(result) } }
                    .padding(.leading, 38)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                // Library poster row only for unstructured (fallback) responses
                if message.structuredResponse == nil {
                    let matches = LibraryMatches.find(in: message.text, shows: shows, movies: movies, teams: teams)
                    if !matches.isEmpty {
                        RecommendedItemsRow(matches: matches)
                            .padding(.leading, 38)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 18)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                _ = visibleMessageIDs.insert(message.id)
            }
        }
    }

    // MARK: - Retry Bubble

    private func retryBubble(lastUserMessage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Couldn't get a response.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Retry") {
                // Remove the failed assistant message and resend
                messages.removeAll { $0.text == "__retry__" }
                if !lastUserMessage.isEmpty { send(lastUserMessage) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DS.Color.ai)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedCornerShape(radius: DS.Radius.lg, corners: [.topLeft, .topRight, .bottomRight]))
        .overlay(
            RoundedCornerShape(radius: DS.Radius.lg, corners: [.topLeft, .topRight, .bottomRight])
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 10) {
            aiAvatar

            TypingDotsView()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedCornerShape(radius: DS.Radius.lg, corners: [.topLeft, .topRight, .bottomRight]))
                .overlay(
                    RoundedCornerShape(radius: DS.Radius.lg, corners: [.topLeft, .topRight, .bottomRight])
                        .stroke(DS.Color.ai.opacity(0.12), lineWidth: 1)
                )

            Spacer(minLength: 56)
        }
    }

    // MARK: - Suggestions

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hero banner
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        LinearGradient(
                            colors: [DS.Color.ai, DS.Color.ai.opacity(0.55)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: DS.Color.ai.opacity(0.4), radius: 8, y: 3)

                    Text("Ask StreamCal")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Text("Ask about your schedule, or get personalized picks — shows, movies, and anime you've never seen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    LinearGradient(
                        colors: [DS.Color.ai.opacity(0.08), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.ai.opacity(0.15), lineWidth: 1)
            )

            // Library chips
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Library")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                FlowLayout(spacing: 8) {
                    ForEach(librarySuggestions, id: \.self) { suggestion in
                        suggestionChip(suggestion, icon: "chevron.right", iconColor: DS.Color.ai)
                    }
                }
            }

            // Discovery chips
            VStack(alignment: .leading, spacing: 8) {
                Text("Discover")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                FlowLayout(spacing: 8) {
                    ForEach(discoverySuggestions, id: \.self) { suggestion in
                        suggestionChip(suggestion, icon: "sparkles", iconColor: DS.Color.ai)
                    }
                }
            }
        }
    }

    private func suggestionChip(_ text: String, icon: String, iconColor: Color) -> some View {
        Button { send(text) } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(.separator).opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        let isEmpty = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask anything — shows, movies, new picks…", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit { if !isEmpty { send(inputText) } }

            Button {
                send(inputText)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(isEmpty || isLoading ? Color(.tertiaryLabel) : Color.accentColor)
                    .clipShape(Circle())
                    .scaleEffect(sendButtonScale)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isEmpty)
            }
            .disabled(isEmpty || isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(inputFocused ? DS.Color.ai.opacity(0.3) : Color(.separator).opacity(0.4), lineWidth: 1)
                .animation(.easeInOut(duration: 0.2), value: inputFocused)
        )
        .shadow(color: .black.opacity(0.07), radius: 12, y: 3)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    // MARK: - Locked State

    private var lockedState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(DS.Color.ai)
            Text("Ask StreamCal is a Pro feature")
                .font(.headline)
            Text("Upgrade to Pro to ask natural language questions about your library and get intelligent, personalized answers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Upgrade to Pro") {
                showingPaywall = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Send

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { sendButtonScale = 1.25 }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6).delay(0.12)) { sendButtonScale = 1.0 }

        inputText = ""
        inputFocused = false
        messages.append(ChatMessage(role: .user, text: trimmed))
        isLoading = true

        let context = StreamCalContext(
            shows: shows, movies: movies, teams: teams,
            preferredPlatforms: preferredPlatforms, today: .now
        )

        Task {
            let reply = await ClaudeService.ask(question: trimmed, context: context)
            isLoading = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            let message: ChatMessage
            if let raw = reply, let structured = parseStructuredResponse(raw) {
                message = ChatMessage(role: .assistant, text: structured.summary ?? "", structuredResponse: structured)
            } else if let raw = reply, !raw.isEmpty {
                // Structured parse failed — show plain text, stripping any code fences
                let cleaned = raw
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                message = ChatMessage(role: .assistant, text: cleaned.isEmpty ? "__retry__" : cleaned)
            } else {
                message = ChatMessage(role: .assistant, text: "__retry__")
            }

            messages.append(message)
            animateTypewriter(for: message)
        }
    }

    // Extract and decode JSON robustly — handles code fences, trailing text, nesting.
    private func parseStructuredResponse(_ raw: String) -> StreamCalResponse? {
        // Strip markdown code fences Claude adds despite instructions
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json") { text = String(text.dropFirst(7)) }
        else if text.hasPrefix("```") { text = String(text.dropFirst(3)) }
        if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try direct decode first
        if let data = text.data(using: .utf8),
           let result = try? JSONDecoder().decode(StreamCalResponse.self, from: data) {
            return result
        }
        // Fall back to extracting the outermost JSON object
        guard let jsonString = extractOutermostJSON(from: text),
              let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StreamCalResponse.self, from: data)
    }

    // Walk the string character-by-character to find the correctly balanced { }.
    // This is immune to: code fences, trailing text, } inside strings.
    private func extractOutermostJSON(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var endIdx: String.Index? = nil

        for idx in text[start...].indices {
            let c = text[idx]
            if escaped { escaped = false; continue }
            if c == "\\" && inString { escaped = true; continue }
            if c == "\"" { inString.toggle(); continue }
            if inString { continue }
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { endIdx = idx; break }
            }
        }
        guard let end = endIdx else { return nil }
        return String(text[start...end])
    }

    // True if the text looks like raw JSON or a code block — so we don't show it to the user.
    private func looksLikeRawJSON(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("{") || t.hasPrefix("```")
    }

    private func animateTypewriter(for message: ChatMessage) {
        typewriterTask?.cancel()

        // Skip typewriter if structured response has no summary to animate
        if message.structuredResponse != nil && message.text.isEmpty {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                _ = visibleMessageIDs.insert(message.id)
            }
            Task { await fetchDiscoveryResults(for: message) }
            return
        }

        typingMessageID = message.id
        typingText = ""
        typewriterTask = Task {
            for char in message.text {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: 14_000_000)
                guard !Task.isCancelled else { break }
                typingText.append(char)
            }
            if !Task.isCancelled {
                withAnimation(.easeIn(duration: 0.15)) { typingMessageID = nil }
                await fetchDiscoveryResults(for: message)
            }
        }
    }

    private func fetchDiscoveryResults(for message: ChatMessage) async {
        var titlesToSearch: [String] = []

        if let structured = message.structuredResponse {
            // Collect all items Claude flagged as not in the library
            let libraryTitles = Set(
                shows.map { $0.title.lowercased() } +
                movies.map { $0.title.lowercased() } +
                animeShows.map { $0.displayTitle.lowercased() }
            )
            titlesToSearch = structured.sections
                .flatMap { $0.items }
                .filter { !($0.isInLibrary ?? false) }
                .map(\.title)
                .filter { !libraryTitles.contains($0.lowercased()) }
        } else {
            // Fallback: extract **bolded** titles from plain text
            guard let regex = try? NSRegularExpression(pattern: #"\*\*([^*]{2,60})\*\*"#) else { return }
            let range = NSRange(message.text.startIndex..., in: message.text)
            let boldedTitles = regex.matches(in: message.text, range: range).compactMap {
                Range($0.range(at: 1), in: message.text).map { String(message.text[$0]) }
            }
            let libraryTitles = Set(
                shows.map { $0.title.lowercased() } +
                movies.map { $0.title.lowercased() } +
                animeShows.map { $0.displayTitle.lowercased() }
            )
            titlesToSearch = boldedTitles.filter { !libraryTitles.contains($0.lowercased()) }
        }

        guard !titlesToSearch.isEmpty else { return }

        var results: [DiscoveryResult] = []
        for title in titlesToSearch.prefix(5) {
            if let result = await searchTMDB(for: title) { results.append(result) }
        }

        if !results.isEmpty {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                discoveryResultsByMessage[message.id] = results
            }
        }
    }

    private func searchTMDB(for title: String) async -> DiscoveryResult? {
        // Try TV first, then movie
        if let show = try? await TMDBService.shared.searchShows(query: title).first,
           show.name.lowercased().hasPrefix(title.lowercased().prefix(6)) {
            return DiscoveryResult(
                title: show.name,
                posterURL: show.posterURL,
                tmdbID: show.id,
                mediaType: .tv
            )
        }
        if let movie = try? await TMDBService.shared.searchMovies(query: title).first,
           movie.title.lowercased().hasPrefix(title.lowercased().prefix(6)) {
            return DiscoveryResult(
                title: movie.title,
                posterURL: movie.posterURL,
                tmdbID: movie.id,
                mediaType: .movie
            )
        }
        return nil
    }

    private func addDiscoveryItem(_ result: DiscoveryResult) async {
        guard addingTmdbID == nil else { return }
        addingTmdbID = result.tmdbID

        do {
            switch result.mediaType {
            case .tv:
                let details = try await TMDBService.shared.fetchShowDetails(tmdbID: result.tmdbID)
                let episodes = try await TMDBService.shared.fetchAllEpisodes(tmdbID: result.tmdbID)
                let providers = try? await TMDBService.shared.fetchWatchProviders(tmdbID: result.tmdbID, mediaType: "tv")
                let show = Show(
                    title: result.title,
                    tmdbID: result.tmdbID,
                    posterURL: result.posterURL?.absoluteString,
                    showStatus: details.status
                )
                show.watchProviderNames = providers?.map(\.providerName) ?? []
                modelContext.insert(show)
                for ep in episodes {
                    let episode = Episode(
                        seasonNumber: ep.seasonNumber,
                        episodeNumber: ep.episodeNumber,
                        title: ep.name ?? "",
                        airDate: ep.parsedAirDate ?? .distantFuture
                    )
                    episode.show = show
                    modelContext.insert(episode)
                }
                try? modelContext.save()

            case .movie:
                let details = try await TMDBService.shared.fetchMovieDetails(tmdbID: result.tmdbID)
                let providers = try? await TMDBService.shared.fetchWatchProviders(tmdbID: result.tmdbID, mediaType: "movie")
                let movie = Movie(
                    title: result.title,
                    tmdbID: result.tmdbID,
                    posterURL: result.posterURL?.absoluteString,
                    overview: details.overview,
                    tagline: details.tagline,
                    genres: details.genres?.map(\.name) ?? [],
                    theatricalReleaseDate: details.usTheatricalDate() ?? .distantFuture,
                    streamingReleaseDate: details.usStreamingDate(),
                    tmdbStatus: details.status
                )
                movie.watchProviderNames = providers?.map(\.providerName) ?? []
                modelContext.insert(movie)
                try? modelContext.save()
            }

            withAnimation { addedFromDiscovery.insert(result.tmdbID) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // Silent failure — user can add manually
        }

        addingTmdbID = nil
    }
}

// MARK: - Structured Response Rendering

struct StructuredResponseView: View {
    let response: StreamCalResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(response.sections) { section in
                SectionCardView(section: section)
            }
        }
    }
}

struct SectionCardView: View {
    let section: StreamCalSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.heading.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .tracking(0.8)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 0) {
                        ItemRowView(item: item)
                        if index < section.items.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
    }
}

struct ItemRowView: View {
    let item: StreamCalItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if item.badgeStyle == "live" {
                LiveBadge()
            } else if let badge = item.badge, !badge.isEmpty {
                Text(badge)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeColor(for: item.badgeStyle).opacity(0.12))
                    .foregroundStyle(badgeColor(for: item.badgeStyle))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func badgeColor(for style: String?) -> Color {
        switch style {
        case "live":   return .red
        case "today":  return .orange
        case "soon":   return Color.accentColor
        case "ai":     return DS.Color.ai
        default:       return .secondary
        }
    }
}

struct LiveBadge: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
                .scaleEffect(pulsing ? 1.35 : 0.75)
                .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: pulsing)
            Text("LIVE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.red.opacity(0.1))
        .clipShape(Capsule())
        .onAppear { pulsing = true }
    }
}

// MARK: - Discovery Result Model

struct DiscoveryResult: Identifiable {
    let id = UUID()
    let title: String
    let posterURL: URL?
    let tmdbID: Int
    enum MediaType { case tv, movie }
    let mediaType: MediaType
}

// MARK: - Discovery Results Row

struct DiscoveryResultsRow: View {
    let results: [DiscoveryResult]
    let addedIDs: Set<Int>
    let addingID: Int?
    let onAdd: (DiscoveryResult) -> Void

    @State private var selectedResult: DiscoveryResult? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add to StreamCal")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(results) { result in
                        DiscoveryPosterCard(
                            result: result,
                            isAdded: addedIDs.contains(result.tmdbID),
                            isLoading: addingID == result.tmdbID,
                            onTap: { selectedResult = result },
                            onAdd: { onAdd(result) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .sheet(item: $selectedResult) { result in
            DiscoveryDetailSheet(result: result, onAdd: {
                onAdd(result)
                selectedResult = nil
            })
        }
    }
}

struct DiscoveryPosterCard: View {
    let result: DiscoveryResult
    let isAdded: Bool
    let isLoading: Bool
    let onTap: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Button(action: onTap) {
                    CachedAsyncImage(url: result.posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            Rectangle()
                                .foregroundStyle(DS.Color.imagePlaceholder)
                                .overlay {
                                    Image(systemName: result.mediaType == .tv ? "sparkles.tv" : "film")
                                        .foregroundStyle(.tertiary)
                                }
                        @unknown default:
                            Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                        }
                    }
                    .frame(width: 78, height: 117)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .stroke(isAdded ? Color.teal : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)

                // Badge — tapping this adds directly
                Button(action: { if !isAdded && !isLoading { onAdd() } }) {
                    ZStack {
                        Circle()
                            .fill(isAdded ? Color.teal : Color.accentColor)
                            .frame(width: 22, height: 22)
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.55)
                                .tint(.white)
                        } else {
                            Image(systemName: isAdded ? "checkmark" : "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .disabled(isAdded || isLoading)
            }

            Text(result.title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 78, alignment: .leading)
        }
    }
}

// MARK: - Discovery Detail Sheet

struct DiscoveryDetailSheet: View {
    let result: DiscoveryResult
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var overview: String? = nil
    @State private var tagline: String? = nil
    @State private var genres: [String] = []
    @State private var year: String? = nil
    @State private var isAdding = false
    @State private var isAdded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Poster + info
                    HStack(alignment: .top, spacing: 16) {
                        CachedAsyncImage(url: result.posterURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Rectangle()
                                    .foregroundStyle(DS.Color.imagePlaceholder)
                                    .overlay {
                                        Image(systemName: result.mediaType == .tv ? "sparkles.tv" : "film")
                                            .foregroundStyle(.tertiary)
                                    }
                            }
                        }
                        .frame(width: 100, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.title)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .lineLimit(3)

                            if let year { Text(year).font(.subheadline).foregroundStyle(.secondary) }

                            if !genres.isEmpty {
                                Text(genres.prefix(3).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Label(result.mediaType == .tv ? "TV Show" : "Movie", systemImage: result.mediaType == .tv ? "tv" : "film")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()

                    if let tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    if let overview {
                        Text(overview)
                            .font(.body)
                            .padding(.horizontal)
                    }

                    // Add button
                    Button {
                        guard !isAdded && !isAdding else { return }
                        isAdding = true
                        onAdd()
                        isAdded = true
                        isAdding = false
                    } label: {
                        HStack {
                            if isAdding {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: isAdded ? "checkmark" : "plus")
                            }
                            Text(isAdded ? "Added to Library" : "Add to StreamCal")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isAdded ? Color.teal : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .disabled(isAdded || isAdding)
                }
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadDetails() }
        }
    }

    private func loadDetails() async {
        if result.mediaType == .tv {
            if let details = try? await TMDBService.shared.fetchShowDetails(tmdbID: result.tmdbID) {
                overview = details.overview
                genres = details.genres?.map(\.name) ?? []
                if let first = details.firstAirDate?.prefix(4) { year = String(first) }
            }
        } else {
            if let details = try? await TMDBService.shared.fetchMovieDetails(tmdbID: result.tmdbID) {
                overview = details.overview
                tagline = details.tagline
                genres = details.genres?.map(\.name) ?? []
                if let rel = details.releaseDate?.prefix(4) { year = String(rel) }
            }
        }
    }
}

// MARK: - Recommended Items Row

struct RecommendedItemsRow: View {
    let matches: LibraryMatches

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(matches.shows) { show in
                    NavigationLink(destination: ShowDetailView(show: show)) {
                        LibraryPosterCard(imageURL: show.posterImageURL, title: show.title)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(matches.movies) { movie in
                    NavigationLink(destination: MovieDetailView(movie: movie)) {
                        LibraryPosterCard(imageURL: movie.posterImageURL, title: movie.title)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(matches.teams) { team in
                    NavigationLink(destination: TeamDetailView(team: team)) {
                        LibraryPosterCard(imageURL: team.badgeImageURL, title: team.name, isSquare: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct LibraryPosterCard: View {
    let imageURL: URL?
    let title: String
    var isSquare: Bool = false

    private var imageHeight: CGFloat { isSquare ? 78 : 117 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            CachedAsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: isSquare ? "trophy" : "sparkles.tv")
                                .foregroundStyle(.tertiary)
                        }
                @unknown default:
                    Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 78, height: imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 78, alignment: .leading)
        }
    }
}

// MARK: - Typing Dots Animation

struct TypingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Rounded Corner Shape

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Flow Layout (wrapping chip layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        height = y + rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
