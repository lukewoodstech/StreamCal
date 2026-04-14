import SwiftUI
import SwiftData

struct MovieDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let movie: Movie
    var onAction: ((ToastMessage) -> Void)? = nil

    private var watchPlatforms: [StreamingPlatform] { movie.matchedStreamingPlatforms }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroHeader
                    .padding(.bottom, DS.Spacing.lg)

                statusCard
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.lg)

                releaseDatesSection
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.lg)

                if let overview = movie.overview, !overview.isEmpty {
                    aboutSection(overview)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.xl)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationBarTitleDisplayMode(.inline)
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
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = movie.posterImageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                    @unknown default:
                        Rectangle().foregroundStyle(DS.Color.imagePlaceholder)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipped()
            } else {
                Rectangle()
                    .foregroundStyle(DS.Color.imagePlaceholder)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 360)

            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(3)

                if let year = movie.theatricalReleaseDate != .distantFuture
                    ? Calendar.current.component(.year, from: movie.theatricalReleaseDate)
                    : nil {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLabel)
                        .font(.headline)
                    if let sub = statusSubtitle {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if !watchPlatforms.isEmpty {
                HStack(spacing: 6) {
                    ForEach(watchPlatforms.prefix(3), id: \.self) { platform in
                        if let url = platform.webURL {
                            Link(destination: url) {
                                Text(platform.rawValue)
                                    .statusBadge(color: platform.badgeColor)
                            }
                        } else {
                            Text(platform.rawValue)
                                .statusBadge(color: platform.badgeColor)
                        }
                    }
                }
            }

        }
        .padding(DS.Spacing.lg)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var statusIcon: String {
        switch movie.releaseStatus {
        case .watched, .streaming: return "play.tv.fill"
        case .released:            return "film.fill"
        case .comingSoon:          return "calendar"
        case .announced:           return "clock"
        }
    }

    private var statusColor: Color {
        switch movie.releaseStatus {
        case .watched, .streaming: return .blue
        case .released:            return DS.Color.movieTheaterRed
        case .comingSoon:          return .orange
        case .announced:           return .secondary
        }
    }

    private var statusLabel: String {
        switch movie.releaseStatus {
        case .watched, .streaming: return "Streaming Now"
        case .released:            return "In Theaters"
        case .comingSoon:          return "Coming Soon"
        case .announced:           return "Announced"
        }
    }

    private var statusSubtitle: String? {
        switch movie.releaseStatus {
        case .comingSoon:
            return movie.theatricalReleaseDate.formatted(.dateTime.month(.wide).day().year())
        case .streaming:
            if let date = movie.streamingReleaseDate {
                return "Since \(date.formatted(.dateTime.month(.abbreviated).day().year()))"
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Release Dates

    @ViewBuilder
    private var releaseDatesSection: some View {
        let hasTheatrical = movie.theatricalReleaseDate != .distantFuture
        let hasStreaming = movie.streamingReleaseDate != nil

        if hasTheatrical || hasStreaming {
            VStack(spacing: 0) {
                if hasTheatrical {
                    HStack {
                        Text("Theatrical Release")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(movie.theatricalReleaseDate.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.subheadline)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, 11)
                }

                if hasTheatrical && hasStreaming { Divider().padding(.leading, DS.Spacing.lg) }

                if let streaming = movie.streamingReleaseDate {
                    HStack {
                        Text("Streaming")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(streaming.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.subheadline)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, 11)
                }

                if !movie.genres.isEmpty {
                    Divider().padding(.leading, DS.Spacing.lg)
                    HStack {
                        Text("Genres")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(movie.genres.prefix(3).joined(separator: ", "))
                            .font(.subheadline)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, 11)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
    }

    // MARK: - About

    private func aboutSection(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let tagline = movie.tagline, !tagline.isEmpty {
                Text("\"\(tagline)\"")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.bottom, DS.Spacing.xs)
            }
            Text("About")
                .font(.headline)
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        MovieDetailView(movie: Movie(
            title: "Dune: Part Two",
            overview: "Follow the mythic journey of Paul Atreides as he unites with Chani and the Fremen.",
            tagline: "Long live the fighters.",
            theatricalReleaseDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
        ))
    }
    .modelContainer(for: [Movie.self], inMemory: true)
}
