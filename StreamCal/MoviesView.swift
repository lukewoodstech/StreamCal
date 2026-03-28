import SwiftUI
import SwiftData

struct MoviesView: View {

    var onAdd: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Movie.createdAt, order: .reverse)
    private var movies: [Movie]

    @State private var toast: ToastMessage? = nil

    private var inTheaters: [Movie] {
        movies.filter { !$0.isArchived && $0.releaseStatus == .released }
              .sorted { $0.theatricalReleaseDate < $1.theatricalReleaseDate }
    }

    private var comingSoon: [Movie] {
        movies.filter { !$0.isArchived && $0.releaseStatus == .comingSoon }
              .sorted { $0.theatricalReleaseDate < $1.theatricalReleaseDate }
    }

    private var announced: [Movie] {
        movies.filter { !$0.isArchived && $0.releaseStatus == .announced }
              .sorted { $0.title < $1.title }
    }

    private var streaming: [Movie] {
        movies.filter { !$0.isArchived && $0.releaseStatus == .streaming }
              .sorted { ($0.streamingReleaseDate ?? .distantFuture) > ($1.streamingReleaseDate ?? .distantFuture) }
    }

    private var watched: [Movie] {
        movies.filter { $0.isWatched && !$0.isArchived }
              .sorted { ($0.watchedAt ?? .distantPast) > ($1.watchedAt ?? .distantPast) }
    }

    var body: some View {
        Group {
            if movies.filter({ !$0.isArchived }).isEmpty {
                ContentUnavailableView {
                    Label("No Movies Yet", systemImage: "film.stack")
                } description: {
                    Text("Search for a movie to track its release.")
                } actions: {
                    Button("Add a Movie") { onAdd?() }
                        .buttonStyle(.bordered)
                }
            } else {
                List {
                    movieSection("In Theaters", movies: inTheaters)
                    movieSection("Coming Soon", movies: comingSoon)
                    movieSection("Streaming Now", movies: streaming)
                    movieSection("Announced", movies: announced)
                    movieSection("Watched", movies: watched)
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await RefreshService.shared.refreshAllMovies(modelContext: modelContext)
                }
            }
        }
        .toast(message: toast) { toast = nil }
    }

    @ViewBuilder
    private func movieSection(_ title: String, movies: [Movie]) -> some View {
        if !movies.isEmpty {
            Section(title) {
                ForEach(movies) { movie in
                    NavigationLink(destination: MovieDetailView(movie: movie, onAction: { toast = $0 })) {
                        MovieRowView(movie: movie)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            let title = movie.title
                            modelContext.delete(movie)
                            toast = .removed(title)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if !movie.isWatched {
                            Button {
                                movie.isWatched = true
                                movie.watchedAt = .now
                                movie.updatedAt = .now
                                if let tmdbID = movie.tmdbID {
                                    NotificationService.shared.cancelMovieNotification(tmdbID: tmdbID)
                                }
                                toast = .watched(movie.title)
                            } label: {
                                Label("Watched", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        } else {
                            Button {
                                movie.isWatched = false
                                movie.watchedAt = nil
                                movie.updatedAt = .now
                                toast = .unwatched(movie.title)
                            } label: {
                                Label("Unwatch", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Movie Row

struct MovieRowView: View {
    let movie: Movie

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: movie.posterImageURL.flatMap {
                URL(string: $0.absoluteString.replacingOccurrences(of: "/w300", with: "/w92"))
            }) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: "film")
                                .foregroundStyle(.tertiary)
                        }
                @unknown default:
                    Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(movie.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    releaseChip
                }

                if let overview = movie.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !movie.genres.isEmpty {
                    Text(movie.genres.prefix(2).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var releaseChip: some View {
        switch movie.releaseStatus {
        case .watched:
            Text("Watched").statusBadge(color: .green)
        case .streaming:
            Text("Streaming").statusBadge(color: .blue)
        case .released:
            Text("In Theaters").statusBadge(color: DS.Color.movieTheaterRed)
        case .comingSoon:
            if movie.theatricalReleaseDate != .distantFuture {
                Text(movie.theatricalReleaseDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .announced:
            Text("TBA")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

}

#Preview {
    NavigationStack {
        MoviesView()
    }
    .modelContainer(for: [Movie.self], inMemory: true)
}
