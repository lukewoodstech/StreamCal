import SwiftUI
import SwiftData

struct AddShowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Pass an existing Show to edit metadata only (no re-import).
    var existingShow: Show? = nil
    /// Called with the show title after a successful import.
    var onAdded: ((String) -> Void)? = nil

    @State private var searchText = ""
    @State private var results: [TMDBShow] = []
    @State private var suggestions: [TMDBShow] = []
    @State private var isLoadingSuggestions = false
    @State private var isSearching = false
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var libraryTMDBIDs: Set<Int> = []

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
            if isImporting {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Importing episodes…")
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
            } else if results.isEmpty && !searchText.isEmpty && !isSearching {
                ContentUnavailableView.search(text: searchText)
            } else if searchText.isEmpty {
                if isLoadingSuggestions {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 20)
                } else if !suggestions.isEmpty {
                    Section("Trending This Week") {
                        ForEach(suggestions) { show in
                            let alreadyAdded = libraryTMDBIDs.contains(show.id)
                            Button {
                                guard !alreadyAdded else { return }
                                Task { await importShow(show) }
                            } label: {
                                SearchResultRow(show: show, alreadyAdded: alreadyAdded)
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyAdded)
                        }
                    }
                }
            } else {
                ForEach(results) { show in
                    let alreadyAdded = libraryTMDBIDs.contains(show.id)
                    Button {
                        guard !alreadyAdded else { return }
                        Task { await importShow(show) }
                    } label: {
                        SearchResultRow(show: show, alreadyAdded: alreadyAdded)
                    }
                    .buttonStyle(.plain)
                    .disabled(alreadyAdded)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search TV shows…")
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

    // MARK: - Search Logic

    private func loadSuggestions() async {
        isLoadingSuggestions = true
        suggestions = (try? await TMDBService.shared.fetchTrendingShows()) ?? []
        isLoadingSuggestions = false
    }

    private func loadLibraryIDs() {
        let descriptor = FetchDescriptor<Show>()
        if let shows = try? modelContext.fetch(descriptor) {
            libraryTMDBIDs = Set(shows.compactMap { $0.tmdbID })
        }
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            isSearching = true
            do {
                let found = try await TMDBService.shared.searchShows(query: trimmed)
                if !Task.isCancelled {
                    results = found
                }
            } catch {
                if !Task.isCancelled {
                    results = []
                }
            }
            isSearching = false
        }
    }

    // MARK: - Import Logic

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

// MARK: - Search Result Row

struct SearchResultRow: View {
    let show: TMDBShow
    let alreadyAdded: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: show.posterThumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.tertiary)
                        }
                @unknown default:
                    Rectangle()
                        .foregroundStyle(Color(.systemGray5))
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
                    Text(year)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let overview = show.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if alreadyAdded {
                Label("In Library", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
                    .labelStyle(.iconOnly)
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

#Preview {
    AddShowSheet()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
