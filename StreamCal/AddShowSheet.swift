import SwiftUI
import SwiftData

private enum ContentSource: String, CaseIterable {
    case tv = "TV Shows"
    case anime = "Anime"
}

struct AddShowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Pass an existing Show to edit metadata only (no re-import).
    var existingShow: Show? = nil
    /// Called with the show title after a successful import.
    var onAdded: ((String) -> Void)? = nil

    @State private var contentSource: ContentSource = .tv
    @State private var searchText = ""

    // TV state
    @State private var tvResults: [TMDBShow] = []
    @State private var tvSuggestions: [TMDBShow] = []
    @State private var libraryTMDBIDs: Set<Int> = []
    @State private var libraryShowsByTMDBID: [Int: Show] = [:]

    // Anime state
    @State private var animeResults: [AniListResult] = []
    @State private var animeSuggestions: [AniListResult] = []
    @State private var libraryAnilistIDs: Set<Int> = []

    // Shared state
    @State private var isLoadingSuggestions = false
    @State private var isSearching = false
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    // Edit-mode fields
    @State private var editPlatforms: Set<String> = []
    @State private var editNotes = ""

    var isEditMode: Bool { existingShow != nil }

    private let selectablePlatforms: [StreamingPlatform] = StreamingPlatform.allCases.filter { $0 != .other }

    var body: some View {
        NavigationStack {
            Group {
                if isEditMode {
                    editForm
                } else {
                    searchView
                }
            }
            .navigationTitle(isEditMode ? "Edit Show" : "Add Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if isEditMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { saveEdit() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                if let show = existingShow {
                    let current = show.platforms.isEmpty ? [show.platform] : show.platforms
                    editPlatforms = Set(current)
                    editNotes = show.notes
                }
                loadLibraryIDs()
                if !isEditMode {
                    Task { await loadSuggestions() }
                }
            }
        }
    }

    // MARK: - Search View

    private var searchView: some View {
        List {
            if !isEditMode {
                // Source picker at the top
                Picker("Content Source", selection: $contentSource) {
                    ForEach(ContentSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .onChange(of: contentSource) { _, _ in
                    searchText = ""
                    tvResults = []
                    animeResults = []
                    isSearching = false
                    searchTask?.cancel()
                    Task { await loadSuggestions() }
                }
            }

            if isImporting {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Importing…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 40)
            } else if let error = importError {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Import failed", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if searchText.isEmpty {
                // Suggestions
                if isLoadingSuggestions {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 20)
                } else if contentSource == .tv, !tvSuggestions.isEmpty {
                    Section("Trending This Week") {
                        ForEach(tvSuggestions) { show in
                            let inLibrary = libraryTMDBIDs.contains(show.id)
                            if inLibrary, let existing = libraryShowsByTMDBID[show.id] {
                                NavigationLink(destination: ShowDetailView(show: existing)) {
                                    SearchResultRow(show: show, alreadyAdded: true)
                                }
                            } else {
                                Button {
                                    Task { await importShow(show) }
                                } label: {
                                    SearchResultRow(show: show, alreadyAdded: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else if contentSource == .anime, !animeSuggestions.isEmpty {
                    Section("Trending This Week") {
                        ForEach(animeSuggestions) { result in
                            let inLibrary = libraryAnilistIDs.contains(result.id)
                            Button {
                                guard !inLibrary else { return }
                                Task { await importAnime(result) }
                            } label: {
                                AnimeSearchResultRow(result: result, isInLibrary: inLibrary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if contentSource == .tv {
                // TV search results
                if tvResults.isEmpty && !isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(tvResults) { show in
                        let inLibrary = libraryTMDBIDs.contains(show.id)
                        if inLibrary, let existing = libraryShowsByTMDBID[show.id] {
                            NavigationLink(destination: ShowDetailView(show: existing)) {
                                SearchResultRow(show: show, alreadyAdded: true)
                            }
                        } else {
                            Button {
                                Task { await importShow(show) }
                            } label: {
                                SearchResultRow(show: show, alreadyAdded: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                // Anime search results
                if animeResults.isEmpty && !isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(animeResults) { result in
                        let inLibrary = libraryAnilistIDs.contains(result.id)
                        Button {
                            guard !inLibrary else { return }
                            Task { await importAnime(result) }
                        } label: {
                            AnimeSearchResultRow(result: result, isInLibrary: inLibrary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: contentSource == .tv ? "Search TV shows…" : "Search anime…"
        )
        .onChange(of: searchText) { _, newValue in
            scheduleSearch(query: newValue)
        }
        .overlay {
            if isSearching {
                ProgressView()
            }
        }
    }

    // MARK: - Edit Form

    private var editForm: some View {
        Form {
            Section("Platforms") {
                platformRows
            }
            Section("Notes") {
                TextField("Optional notes…", text: $editNotes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    @ViewBuilder
    private var platformRows: some View {
        ForEach(selectablePlatforms) { p in
            platformRow(p)
        }
    }

    private func platformRow(_ p: StreamingPlatform) -> some View {
        Button {
            if editPlatforms.contains(p.rawValue) {
                editPlatforms.remove(p.rawValue)
            } else {
                editPlatforms.insert(p.rawValue)
            }
        } label: {
            HStack {
                Text(p.rawValue)
                    .foregroundStyle(.primary)
                Spacer()
                if editPlatforms.contains(p.rawValue) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Load Suggestions

    private func loadSuggestions() async {
        isLoadingSuggestions = true
        if contentSource == .tv {
            tvSuggestions = (try? await TMDBService.shared.fetchTrendingShows()) ?? []
        } else {
            animeSuggestions = (try? await AniListService.shared.fetchTrending()) ?? []
        }
        isLoadingSuggestions = false
    }

    private func loadLibraryIDs() {
        if let shows = try? modelContext.fetch(FetchDescriptor<Show>()) {
            libraryTMDBIDs = Set(shows.compactMap { $0.tmdbID })
            libraryShowsByTMDBID = Dictionary(uniqueKeysWithValues: shows.compactMap { show in
                show.tmdbID.map { ($0, show) }
            })
        }
        if let anime = try? modelContext.fetch(FetchDescriptor<AnimeShow>()) {
            libraryAnilistIDs = Set(anime.map { $0.anilistID })
        }
    }

    // MARK: - Search

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            tvResults = []
            animeResults = []
            isSearching = false
            return
        }
        let source = contentSource
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            isSearching = true
            if source == .tv {
                let found = (try? await TMDBService.shared.searchShows(query: trimmed)) ?? []
                if !Task.isCancelled { tvResults = found }
            } else {
                let found = (try? await AniListService.shared.search(trimmed)) ?? []
                if !Task.isCancelled { animeResults = found }
            }
            isSearching = false
        }
    }

    // MARK: - Import TV Show

    private func importShow(_ tmdbShow: TMDBShow) async {
        isImporting = true
        importError = nil
        do {
            let details = try await TMDBService.shared.fetchShowDetails(tmdbID: tmdbShow.id)
            let matchedPlatforms = platformsFromNetworks(details.networks)

            let show = Show(
                title: tmdbShow.name,
                platform: matchedPlatforms.first ?? StreamingPlatform.other.rawValue,
                notes: "",
                tmdbID: tmdbShow.id,
                posterURL: tmdbShow.posterURL?.absoluteString,
                overview: tmdbShow.overview,
                showStatus: details.status
            )
            show.platforms = matchedPlatforms
            modelContext.insert(show)

            let allEpisodes = try await TMDBService.shared.fetchAllEpisodes(tmdbID: tmdbShow.id)
            for ep in allEpisodes {
                let airDate = ep.parsedAirDate ?? Date.distantFuture
                let episode = Episode(
                    seasonNumber: ep.seasonNumber,
                    episodeNumber: ep.episodeNumber,
                    title: ep.name ?? "",
                    airDate: airDate,
                    isWatched: false
                )
                episode.show = show
                modelContext.insert(episode)
            }

            await NotificationService.shared.scheduleNotifications(for: show)
            let title = show.title
            dismiss()
            onAdded?(title)
        } catch {
            importError = error.localizedDescription
            isImporting = false
        }
    }

    // MARK: - Import Anime

    private func importAnime(_ result: AniListResult) async {
        isImporting = true
        importError = nil
        do {
            let detail = try await AniListService.shared.fetchDetails(anilistID: result.id)
            let show = AnimeShow(
                anilistID: detail.id,
                titleRomaji: detail.titleRomaji,
                titleEnglish: detail.titleEnglish,
                coverImageURL: detail.coverImageURL,
                overview: detail.overview,
                animeStatus: detail.status,
                totalEpisodes: detail.totalEpisodes,
                genres: detail.genres
            )
            modelContext.insert(show)

            for (epNum, airDate) in detail.airedEpisodes {
                let ep = AnimeEpisode(episodeNumber: epNum, airDate: airDate)
                ep.show = show
                modelContext.insert(ep)
            }
            if let next = detail.nextAiringEpisode {
                let nextDate = Date(timeIntervalSince1970: Double(next.airingAt))
                if !detail.airedEpisodes.contains(where: { $0.episodeNumber == next.episode }) {
                    let ep = AnimeEpisode(episodeNumber: next.episode, airDate: nextDate)
                    ep.show = show
                    modelContext.insert(ep)
                }
            }

            try? modelContext.save()
            libraryAnilistIDs.insert(result.id)
            let title = show.displayTitle
            dismiss()
            onAdded?(title)
        } catch {
            importError = error.localizedDescription
            isImporting = false
        }
    }

    // MARK: - Edit Save

    private func saveEdit() {
        guard let show = existingShow else { return }
        let selected = Array(editPlatforms).sorted()
        show.platforms = selected
        show.platform = selected.first ?? StreamingPlatform.other.rawValue
        show.notes = editNotes
        show.updatedAt = .now
        dismiss()
    }

    // MARK: - Helpers

    private func platformsFromNetworks(_ networks: [TMDBNetwork]?) -> [String] {
        guard let networks, !networks.isEmpty else { return [StreamingPlatform.other.rawValue] }
        var matched: [String] = []
        for name in networks.map({ $0.name.lowercased() }) {
            let p: StreamingPlatform?
            if name.contains("netflix")                            { p = .netflix }
            else if name.contains("hulu")                          { p = .hulu }
            else if name.contains("disney")                        { p = .disneyPlus }
            else if name.contains("max") || name.contains("hbo")  { p = .max }
            else if name.contains("apple")                         { p = .appleTV }
            else if name.contains("amazon") || name.contains("prime") { p = .amazonPrime }
            else if name.contains("peacock")                       { p = .peacock }
            else if name.contains("paramount") || name.contains("showtime") { p = .paramountPlus }
            else if name.contains("starz")                         { p = .starz }
            else if name.contains("mgm")                           { p = .mgmPlus }
            else if name.contains("amc")                           { p = .amcPlus }
            else if name.contains("fx") || name.contains("fxx")   { p = .fx }
            else if name.contains("crunchyroll")                   { p = .crunchyroll }
            else if name.contains("discovery")                     { p = .discoveryPlus }
            else if name.contains("espn")                          { p = .espnPlus }
            else if name.contains("britbox")                       { p = .britbox }
            else if name.contains("shudder")                       { p = .shudder }
            else if name.contains("fubo")                          { p = .fubo }
            else if name.contains("tubi")                          { p = .tubi }
            else if name.contains("pluto")                         { p = .plutoTV }
            else if name.contains("nbc")                           { p = .nbc }
            else if name == "abc" || name.contains("abc (us)")     { p = .abc }
            else if name.contains("cbs")                           { p = .cbs }
            else if name == "fox" || name.contains("fox broadcasting") { p = .fox }
            else if name.contains("pbs")                           { p = .pbs }
            else                                                   { p = nil }

            if let p, !matched.contains(p.rawValue) { matched.append(p.rawValue) }
        }
        return matched.isEmpty ? [StreamingPlatform.other.rawValue] : matched
    }
}

// MARK: - TV Search Result Row

struct SearchResultRow: View {
    let show: TMDBShow
    let alreadyAdded: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: show.posterThumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(Color(.systemGray5))
                        .overlay { Image(systemName: "tv").foregroundStyle(.tertiary) }
                @unknown default:
                    Rectangle().foregroundStyle(Color(.systemGray5))
                }
            }
            .frame(width: 46, height: 69)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(alreadyAdded ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(show.name)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(alreadyAdded ? .secondary : .primary)
                if let year = show.firstAirDate?.prefix(4) {
                    Text(year).font(.caption).foregroundStyle(.secondary)
                }
                if let overview = show.overview, !overview.isEmpty {
                    Text(overview).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                }
            }

            Spacer()

            if alreadyAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.large)
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accentColor)
                    .imageScale(.large)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Anime Search Result Row

struct AnimeSearchResultRow: View {
    let result: AniListResult
    let isInLibrary: Bool

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: result.coverImageURL.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay { Image(systemName: "sparkles.tv").foregroundStyle(.tertiary) }
                @unknown default:
                    Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 46, height: 69)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isInLibrary ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(isInLibrary ? .secondary : .primary)
                if let eng = result.titleEnglish, eng != result.titleRomaji {
                    Text(result.titleRomaji).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(animeStatusLabel(result.status)).font(.caption).foregroundStyle(.secondary)
                    if let total = result.totalEpisodes {
                        Text("· \(total) eps").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if let overview = result.overview, !overview.isEmpty {
                    Text(overview).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                }
            }

            Spacer()

            if isInLibrary {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.large)
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accentColor)
                    .imageScale(.large)
            }
        }
        .padding(.vertical, 4)
    }

    private func animeStatusLabel(_ status: String) -> String {
        switch status {
        case "RELEASING": return "Airing"
        case "FINISHED": return "Finished"
        case "NOT_YET_RELEASED": return "Coming Soon"
        case "CANCELLED": return "Cancelled"
        case "HIATUS": return "On Hiatus"
        default: return status
        }
    }
}

#Preview {
    AddShowSheet()
        .modelContainer(for: [Show.self, Episode.self, AnimeShow.self, AnimeEpisode.self], inMemory: true)
}
