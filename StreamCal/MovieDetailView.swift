import SwiftUI
import SwiftData

struct MovieDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let movie: Movie
    var onAction: ((ToastMessage) -> Void)? = nil

    var body: some View {
        List {
            posterSection
            infoSection
            if let overview = movie.overview, !overview.isEmpty {
                Section("Overview") {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            actionsSection
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        movie.notificationsEnabled.toggle()
                        if !movie.notificationsEnabled, let tmdbID = movie.tmdbID {
                            NotificationService.shared.cancelMovieNotification(tmdbID: tmdbID)
                        } else {
                            Task { await NotificationService.shared.scheduleNotification(for: movie) }
                        }
                    } label: {
                        Label(
                            movie.notificationsEnabled ? "Mute Notifications" : "Unmute Notifications",
                            systemImage: movie.notificationsEnabled ? "bell.slash" : "bell"
                        )
                    }
                    Divider()
                    Button(role: .destructive) {
                        let title = movie.title
                        modelContext.delete(movie)
                        dismiss()
                        onAction?(.removed(title))
                    } label: {
                        Label("Remove from Library", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Sections

    private var posterSection: some View {
        Section {
            HStack {
                Spacer()
                AsyncImage(url: movie.posterImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .failure, .empty:
                        RoundedRectangle(cornerRadius: 12)
                            .foregroundStyle(Color(.systemGray5))
                            .overlay {
                                Image(systemName: "film")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                    @unknown default:
                        RoundedRectangle(cornerRadius: 12)
                            .foregroundStyle(Color(.systemGray5))
                    }
                }
                .frame(width: 160, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                Spacer()
            }
            .listRowBackground(Color.clear)
            .padding(.vertical, 8)
        }
    }

    private var infoSection: some View {
        Section {
            if let tagline = movie.tagline, !tagline.isEmpty {
                Text("\"\(tagline)\"")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
            }

            if !movie.genres.isEmpty {
                LabeledContent("Genres") {
                    Text(movie.genres.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            LabeledContent("Theatrical Release") {
                if movie.theatricalReleaseDate == .distantFuture {
                    Text("TBA").foregroundStyle(.secondary)
                } else {
                    Text(movie.theatricalReleaseDate, style: .date)
                        .foregroundStyle(.secondary)
                }
            }

            if let streaming = movie.streamingReleaseDate {
                LabeledContent("Streaming") {
                    Text(streaming, style: .date)
                        .foregroundStyle(.secondary)
                }
            }

            if let status = movie.tmdbStatus {
                LabeledContent("Status") {
                    Text(status).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            if movie.isWatched {
                Button {
                    movie.isWatched = false
                    movie.watchedAt = nil
                    movie.updatedAt = .now
                    onAction?(.unwatched(movie.title))
                } label: {
                    Label("Mark as Unwatched", systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                Button {
                    movie.isWatched = true
                    movie.watchedAt = .now
                    movie.updatedAt = .now
                    if let tmdbID = movie.tmdbID {
                        NotificationService.shared.cancelMovieNotification(tmdbID: tmdbID)
                    }
                    onAction?(.watched(movie.title))
                } label: {
                    Label("Mark as Watched", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MovieDetailView(movie: Movie(
            title: "Dune: Part Two",
            overview: "Follow the mythic journey of Paul Atreides.",
            theatricalReleaseDate: Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        ))
    }
    .modelContainer(for: [Movie.self], inMemory: true)
}
