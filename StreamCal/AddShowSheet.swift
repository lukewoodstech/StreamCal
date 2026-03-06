import SwiftUI
import SwiftData

struct AddShowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Pass an existing Show to edit metadata only (no re-import).
    var existingShow: Show? = nil

    @State private var searchText = ""
    @State private var results: [TMDBShow] = []
    @State private var isSearching = false
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var libraryTMDBIDs: Set<Int> = []

    // Edit-mode fields
    @State private var editPlatform = StreamingPlatform.netflix.rawValue
    @State private var editNotes = ""

    var isEditMode: Bool { existingShow != nil }

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
                    editPlatform = show.platform
                    editNotes = show.notes
                }
                loadLibraryIDs()
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
            Section("Platform") {
                Picker("Platform", selection: $editPlatform) {
                    ForEach(StreamingPlatform.allCases, id: \.rawValue) { p in
                        Text(p.rawValue).tag(p.rawValue)
                    }
                }
            }
            Section("Notes") {
                TextField("Optional notes…", text: $editNotes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    // MARK: - Search Logic

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
            let platform = platformFromNetworks(details.networks)

            let show = Show(
                title: tmdbShow.name,
                platform: platform,
                notes: "",
                tmdbID: tmdbShow.id,
                posterURL: tmdbShow.posterURL?.absoluteString,
                overview: tmdbShow.overview,
                showStatus: details.status
            )
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

            dismiss()
        } catch {
            importError = error.localizedDescription
            isImporting = false
        }
    }

    // MARK: - Edit Save

    private func saveEdit() {
        guard let show = existingShow else { return }
        show.platform = editPlatform
        show.notes = editNotes
        show.updatedAt = .now
        dismiss()
    }

    // MARK: - Helpers

    private func platformFromNetworks(_ networks: [TMDBNetwork]?) -> String {
        guard let networks else { return StreamingPlatform.other.rawValue }
        let names = networks.map { $0.name.lowercased() }
        if names.contains(where: { $0.contains("netflix") }) { return StreamingPlatform.netflix.rawValue }
        if names.contains(where: { $0.contains("hulu") }) { return StreamingPlatform.hulu.rawValue }
        if names.contains(where: { $0.contains("disney") }) { return StreamingPlatform.disneyPlus.rawValue }
        if names.contains(where: { $0.contains("max") || $0.contains("hbo") }) { return StreamingPlatform.max.rawValue }
        if names.contains(where: { $0.contains("apple") }) { return StreamingPlatform.appleTV.rawValue }
        if names.contains(where: { $0.contains("amazon") || $0.contains("prime") }) { return StreamingPlatform.amazonPrime.rawValue }
        if names.contains(where: { $0.contains("peacock") }) { return StreamingPlatform.peacock.rawValue }
        if names.contains(where: { $0.contains("paramount") }) { return StreamingPlatform.paramountPlus.rawValue }
        return StreamingPlatform.other.rawValue
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
