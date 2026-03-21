import SwiftUI
import SwiftData

struct LibraryView: View {

    /// When false, the view is embedded in LibraryContainerView which provides the NavigationStack.
    var standalone: Bool = true

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Show.createdAt, order: .reverse)
    private var shows: [Show]

    @State private var showingAddShow = false
    @State private var addedShowTitle: String? = nil

    var airingShows: [Show] {
        shows
            .filter { !$0.isArchived && $0.nextUpcomingEpisode != nil && $0.nextUpcomingEpisode?.airDate != .distantFuture }
            .sorted { ($0.nextUpcomingEpisode?.airDate ?? .distantFuture) < ($1.nextUpcomingEpisode?.airDate ?? .distantFuture) }
    }

    var betweenSeasonsShows: [Show] {
        shows
            .filter { !$0.isArchived && ($0.nextUpcomingEpisode == nil || $0.nextUpcomingEpisode?.airDate == .distantFuture) }
            .sorted { $0.title < $1.title }
    }

    var archivedShows: [Show] { shows.filter { $0.isArchived } }

    var body: some View {
        if standalone {
            NavigationStack { innerBody.navigationTitle("Library") }
        } else {
            innerBody
        }
    }

    @ViewBuilder
    private var innerBody: some View {
        Group {
                if shows.isEmpty {
                    ContentUnavailableView(
                        "No Shows Yet",
                        systemImage: "rectangle.stack.fill",
                        description: Text("Tap + to add your first show.")
                    )
                } else {
                    List {
                        if !airingShows.isEmpty {
                            Section("Airing") {
                                ForEach(airingShows) { show in
                                    NavigationLink(destination: ShowDetailView(show: show)) {
                                        ShowRowView(show: show)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            modelContext.delete(show)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            show.isArchived = true
                                            show.updatedAt = .now
                                        } label: {
                                            Label("Archive", systemImage: "archivebox")
                                        }
                                        .tint(.orange)
                                    }
                                }
                            }
                        }

                        if !betweenSeasonsShows.isEmpty {
                            Section("Between Seasons") {
                                ForEach(betweenSeasonsShows) { show in
                                    NavigationLink(destination: ShowDetailView(show: show)) {
                                        ShowRowView(show: show)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            modelContext.delete(show)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            show.isArchived = true
                                            show.updatedAt = .now
                                        } label: {
                                            Label("Archive", systemImage: "archivebox")
                                        }
                                        .tint(.orange)
                                    }
                                }
                            }
                        }

                        if !archivedShows.isEmpty {
                            Section("Archived") {
                                ForEach(archivedShows) { show in
                                    NavigationLink(destination: ShowDetailView(show: show)) {
                                        ShowRowView(show: show)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            modelContext.delete(show)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            show.isArchived = false
                                            show.updatedAt = .now
                                        } label: {
                                            Label("Unarchive", systemImage: "tray.and.arrow.up")
                                        }
                                        .tint(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .refreshable {
                        await RefreshService.shared.refreshAllShows(modelContext: modelContext)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddShow = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddShow) {
                AddShowSheet(onAdded: { title in
                    addedShowTitle = title
                })
            }
            .overlay(alignment: .bottom) {
                if let title = addedShowTitle {
                    AddedToastView(showTitle: title)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    addedShowTitle = nil
                                }
                            }
                        }
                        .padding(.bottom, 16)
                }
            }
            .animation(.spring(duration: 0.4), value: addedShowTitle)
    }
}

// MARK: - Added Toast

struct AddedToastView: View {
    let showTitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Added to Library")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(showTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
}

// MARK: - Show Row

struct ShowRowView: View {
    let show: Show

    private var progress: ShowProgress { WatchPlanner.progress(for: show) }

    private var posterURL: URL? {
        guard let s = show.posterURL else { return nil }
        return URL(string: s)
    }

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: posterURL) { phase in
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
                                .imageScale(.small)
                        }
                @unknown default:
                    Rectangle()
                        .foregroundStyle(Color(.systemGray5))
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(show.title)
                        .font(.headline)
                        .lineLimit(1)
                    if !show.notificationsEnabled {
                        Image(systemName: "bell.slash.fill")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    PlatformBadges(show: show)
                }

                // Progress line
                HStack(spacing: 5) {
                    Image(systemName: progressIcon)
                        .imageScale(.small)
                        .foregroundStyle(progressColor)
                    Text(progress.progressLabel)
                        .font(.caption)
                        .foregroundStyle(progressColor)
                        .lineLimit(1)
                }

                // Detail line — "Up to date through S2E5" etc
                if let detail = progress.progressDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var progressIcon: String {
        if let upcoming = progress.nextUpcoming {
            return Calendar.current.isDateInToday(upcoming.airDate) ? "star.fill" : "calendar"
        }
        if progress.isFullyCaughtUp { return "checkmark.circle.fill" }
        return "tv"
    }

    private var progressColor: Color {
        if let upcoming = progress.nextUpcoming {
            return Calendar.current.isDateInToday(upcoming.airDate) ? .orange : .secondary
        }
        if progress.isFullyCaughtUp { return .green }
        return .secondary
    }
}

/// Shows all platforms for a given show, falling back to the legacy single-platform field.
struct PlatformBadges: View {
    let show: Show

    private var platforms: [String] {
        show.platforms.isEmpty ? [show.platform] : show.platforms
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(platforms, id: \.self) { platform in
                PlatformBadge(platform: platform)
            }
        }
    }
}

struct PlatformBadge: View {
    let platform: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        let badge = Text(platform)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(platformColor.opacity(0.15))
            .foregroundStyle(platformColor)
            .clipShape(Capsule())

        if let url = StreamingPlatform(rawValue: platform)?.webURL {
            Button { openURL(url) } label: { badge }
                .buttonStyle(.plain)
        } else {
            badge
        }
    }

    private var platformColor: Color {
        switch StreamingPlatform(rawValue: platform) {
        case .netflix:       return .red
        case .hulu:          return .green
        case .disneyPlus:    return .blue
        case .max:           return .purple
        case .appleTV:       return .primary
        case .amazonPrime:   return .cyan
        case .peacock:       return .indigo
        case .paramountPlus: return .teal
        case .starz:         return Color(red: 0.1, green: 0.3, blue: 0.7)
        case .mgmPlus:       return .orange
        case .amcPlus:       return Color(red: 0.8, green: 0.1, blue: 0.1)
        case .fx:            return .primary
        case .crunchyroll:   return .orange
        case .discoveryPlus: return .blue
        case .espnPlus:      return .red
        case .britbox:       return Color(red: 0.0, green: 0.35, blue: 0.75)
        case .shudder:       return .purple
        case .fubo:          return Color(red: 0.0, green: 0.6, blue: 0.3)
        case .tubi:          return Color(red: 0.9, green: 0.1, blue: 0.4)
        case .plutoTV:       return .indigo
        case .nbc:           return Color(red: 0.9, green: 0.5, blue: 0.0)
        case .abc:           return .secondary
        case .cbs:           return .blue
        case .fox:           return Color(red: 0.9, green: 0.6, blue: 0.0)
        case .pbs:           return .blue
        case .other, nil:    return .secondary
        }
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
