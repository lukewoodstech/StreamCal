import SwiftUI
import SwiftData

struct MoviesView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Movie.createdAt, order: .reverse)
    private var movies: [Movie]

    @State private var showingAddMovie = false
    @State private var addedMovieTitle: String? = nil

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
                ContentUnavailableView(
                    "No Movies Yet",
                    systemImage: "film.stack",
                    description: Text("Tap + to add a movie.")
                )
            } else {
                List {
                    movieSection("In Theaters", movies: inTheaters)
                    movieSection("Coming Soon", movies: comingSoon)
                    movieSection("Streaming Now", movies: streaming)
                    movieSection("Announced", movies: announced)
                    movieSection("Watched", movies: watched)
                }
                .listStyle(.plain)
                .refreshable {
                    await RefreshService.shared.refreshAllMovies(modelContext: modelContext)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddMovie = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddMovie) {
            AddMovieSheet(onAdded: { title in addedMovieTitle = title })
        }
        .overlay(alignment: .bottom) {
            if let title = addedMovieTitle {
                AddedToastView(showTitle: title)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeOut(duration: 0.3)) { addedMovieTitle = nil }
                        }
                    }
                    .padding(.bottom, 16)
            }
        }
        .animation(.spring(duration: 0.4), value: addedMovieTitle)
    }

    @ViewBuilder
    private func movieSection(_ title: String, movies: [Movie]) -> some View {
        if !movies.isEmpty {
            Section(title) {
                ForEach(movies) { movie in
                    NavigationLink(destination: MovieDetailView(movie: movie)) {
                        MovieRowView(movie: movie)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(movie)
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
                            } label: {
                                Label("Watched", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        } else {
                            Button {
                                movie.isWatched = false
                                movie.watchedAt = nil
                                movie.updatedAt = .now
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
            AsyncImage(url: movie.posterImageURL.flatMap {
                URL(string: $0.absoluteString.replacingOccurrences(of: "/w300", with: "/w92"))
            }) { phase in
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
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 6))

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
            statusBadge("Watched", color: .green)
        case .streaming:
            statusBadge("Streaming", color: .blue)
        case .released:
            statusBadge("In Theaters", color: Color(red: 0.95, green: 0.35, blue: 0.35))
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

    private func statusBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        MoviesView()
    }
    .modelContainer(for: [Movie.self], inMemory: true)
}
