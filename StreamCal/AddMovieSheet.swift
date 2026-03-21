import SwiftUI
import SwiftData

struct AddMovieSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var onAdded: ((String) -> Void)? = nil

    @State private var searchText = ""
    @State private var results: [TMDBMovie] = []
    @State private var isSearching = false
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var libraryTMDBIDs: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                if isImporting {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Adding movie…")
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
                    ForEach(results) { movie in
                        let alreadyAdded = libraryTMDBIDs.contains(movie.id)
                        Button {
                            guard !alreadyAdded else { return }
                            Task { await importMovie(movie) }
                        } label: {
                            MovieSearchResultRow(movie: movie, alreadyAdded: alreadyAdded)
                        }
                        .buttonStyle(.plain)
                        .disabled(alreadyAdded)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search movies…"
            )
            .onChange(of: searchText) { _, newValue in scheduleSearch(query: newValue) }
            .overlay {
                if isSearching { ProgressView() }
            }
            .navigationTitle("Add Movie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { loadLibraryIDs() }
        }
    }

    // MARK: - Search

    private func loadLibraryIDs() {
        let descriptor = FetchDescriptor<Movie>()
        if let movies = try? modelContext.fetch(descriptor) {
            libraryTMDBIDs = Set(movies.compactMap { $0.tmdbID })
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
                let found = try await TMDBService.shared.searchMovies(query: trimmed)
                if !Task.isCancelled { results = found }
            } catch {
                if !Task.isCancelled { results = [] }
            }
            isSearching = false
        }
    }

    // MARK: - Import

    private func importMovie(_ tmdbMovie: TMDBMovie) async {
        isImporting = true
        importError = nil
        do {
            let details = try await TMDBService.shared.fetchMovieDetails(tmdbID: tmdbMovie.id)

            let movie = Movie(
                title: tmdbMovie.title,
                tmdbID: tmdbMovie.id,
                posterURL: tmdbMovie.posterURL?.absoluteString,
                overview: details.overview ?? tmdbMovie.overview,
                tagline: details.tagline,
                genres: details.genres?.map(\.name) ?? [],
                theatricalReleaseDate: details.usTheatricalDate() ?? .distantFuture,
                streamingReleaseDate: details.usStreamingDate(),
                tmdbStatus: details.status
            )
            modelContext.insert(movie)
            try? modelContext.save()

            await NotificationService.shared.scheduleNotification(for: movie)

            let title = movie.title
            dismiss()
            onAdded?(title)
        } catch {
            importError = error.localizedDescription
            isImporting = false
        }
    }
}

// MARK: - Search Result Row

struct MovieSearchResultRow: View {
    let movie: TMDBMovie
    let alreadyAdded: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: movie.posterThumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "film")
                                .foregroundStyle(.tertiary)
                        }
                @unknown default:
                    Rectangle().foregroundStyle(Color(.systemGray5))
                }
            }
            .frame(width: 46, height: 69)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(alreadyAdded ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(alreadyAdded ? .secondary : .primary)
                if let year = movie.releaseDate?.prefix(4) {
                    Text(year)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let overview = movie.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
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

#Preview {
    AddMovieSheet()
        .modelContainer(for: [Movie.self], inMemory: true)
}
