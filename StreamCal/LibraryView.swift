import SwiftUI
import SwiftData

struct LibraryView: View {

    var standalone: Bool = true
    var searchText: String = ""
    var onAdd: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Show.createdAt, order: .reverse)
    private var shows: [Show]

    @Query(sort: \AnimeShow.titleRomaji)
    private var animeShows: [AnimeShow]

    @State private var showingAddShow = false
    @State private var actionToast: ToastMessage? = nil

    // MARK: - TV show sections

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

    // MARK: - Anime sections

    var airingAnime: [AnimeShow] {
        animeShows
            .filter { !$0.isArchived && $0.animeStatus == "RELEASING" && $0.nextUpcomingEpisode != nil }
            .sorted { ($0.nextUpcomingEpisode?.airDate ?? .distantFuture) < ($1.nextUpcomingEpisode?.airDate ?? .distantFuture) }
    }

    var comingSoonAnime: [AnimeShow] {
        animeShows
            .filter { !$0.isArchived && $0.animeStatus == "NOT_YET_RELEASED" }
            .sorted { $0.displayTitle < $1.displayTitle }
    }

    var onHiatusAnime: [AnimeShow] {
        animeShows
            .filter { !$0.isArchived && ($0.animeStatus == "HIATUS" || ($0.animeStatus == "RELEASING" && $0.nextUpcomingEpisode == nil)) }
            .sorted { $0.displayTitle < $1.displayTitle }
    }

    var finishedAnime: [AnimeShow] {
        animeShows
            .filter { !$0.isArchived && ($0.animeStatus == "FINISHED" || $0.animeStatus == "CANCELLED") }
            .sorted { $0.displayTitle < $1.displayTitle }
    }

    var archivedAnime: [AnimeShow] { animeShows.filter { $0.isArchived } }

    private var isEmpty: Bool { shows.isEmpty && animeShows.isEmpty }
    private var isSearching: Bool { !searchText.isEmpty }

    private var filteredShows: [Show] {
        let q = searchText.lowercased()
        return shows.filter { $0.title.lowercased().contains(q) }
            .sorted { $0.title < $1.title }
    }

    private var filteredAnime: [AnimeShow] {
        let q = searchText.lowercased()
        return animeShows.filter {
            $0.displayTitle.lowercased().contains(q) ||
            $0.titleRomaji.lowercased().contains(q)
        }
        .sorted { $0.displayTitle < $1.displayTitle }
    }

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
            if isSearching {
                let allResults = filteredShows.isEmpty && filteredAnime.isEmpty
                if allResults {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filteredShows) { show in
                            NavigationLink(destination: ShowDetailView(show: show)) {
                                ShowRowView(show: show)
                            }
                        }
                        ForEach(filteredAnime) { anime in
                            animeRow(anime)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            } else if isEmpty {
                ContentUnavailableView {
                    Label("Your Library is Empty", systemImage: "rectangle.stack.fill")
                } description: {
                    Text("Add TV shows, movies, and anime to start tracking what's coming up.")
                } actions: {
                    Button("Add a Show") { standalone ? (showingAddShow = true) : onAdd?() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    // MARK: Airing (TV + Anime mixed, sorted by next air date)
                    if !airingShows.isEmpty || !airingAnime.isEmpty {
                        Section("Airing") {
                            ForEach(airingShows) { show in
                                NavigationLink(destination: ShowDetailView(show: show)) {
                                    ShowRowView(show: show)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        let title = show.title
                                        modelContext.delete(show)
                                        actionToast = .removed(title)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        let title = show.title
                                        show.isArchived = true
                                        show.updatedAt = .now
                                        actionToast = .archived(title)
                                    } label: { Label("Archive", systemImage: "archivebox") }
                                    .tint(.orange)
                                }
                            }
                            ForEach(airingAnime) { anime in
                                animeRow(anime)
                            }
                        }
                    }

                    // MARK: Coming Soon (anime only)
                    if !comingSoonAnime.isEmpty {
                        Section("Coming Soon") {
                            ForEach(comingSoonAnime) { anime in
                                animeRow(anime)
                            }
                        }
                    }

                    // MARK: Between Seasons (TV) / On Hiatus (Anime)
                    if !betweenSeasonsShows.isEmpty || !onHiatusAnime.isEmpty {
                        Section("Between Seasons") {
                            ForEach(betweenSeasonsShows) { show in
                                NavigationLink(destination: ShowDetailView(show: show)) {
                                    ShowRowView(show: show)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        let title = show.title
                                        modelContext.delete(show)
                                        actionToast = .removed(title)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        let title = show.title
                                        show.isArchived = true
                                        show.updatedAt = .now
                                        actionToast = .archived(title)
                                    } label: { Label("Archive", systemImage: "archivebox") }
                                    .tint(.orange)
                                }
                            }
                            ForEach(onHiatusAnime) { anime in
                                animeRow(anime)
                            }
                        }
                    }

                    // MARK: Finished (anime that's done)
                    if !finishedAnime.isEmpty {
                        Section("Finished") {
                            ForEach(finishedAnime) { anime in
                                animeRow(anime)
                            }
                        }
                    }

                    // MARK: Archived
                    if !archivedShows.isEmpty || !archivedAnime.isEmpty {
                        Section("Archived") {
                            ForEach(archivedShows) { show in
                                NavigationLink(destination: ShowDetailView(show: show)) {
                                    ShowRowView(show: show)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        let title = show.title
                                        modelContext.delete(show)
                                        actionToast = .removed(title)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        let title = show.title
                                        show.isArchived = false
                                        show.updatedAt = .now
                                        actionToast = .unarchived(title)
                                    } label: { Label("Unarchive", systemImage: "tray.and.arrow.up") }
                                    .tint(.blue)
                                }
                            }
                            ForEach(archivedAnime) { anime in
                                animeRow(anime)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await RefreshService.shared.refreshAllShows(modelContext: modelContext) }
                        group.addTask { await RefreshService.shared.refreshAllAnime(modelContext: modelContext) }
                    }
                }
            }
        }
        .toolbar {
            if standalone {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddShow = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddShow) {
            AddShowSheet(onAdded: { _ in })
        }
        .toast(message: actionToast) { actionToast = nil }
    }

    // MARK: - Anime row helper

    @ViewBuilder
    private func animeRow(_ anime: AnimeShow) -> some View {
        LibraryAnimeRowView(anime: anime)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    let title = anime.displayTitle
                    modelContext.delete(anime)
                    actionToast = .removed(title)
                } label: { Label("Delete", systemImage: "trash") }
            }
            .swipeActions(edge: .leading) {
                Button {
                    let title = anime.displayTitle
                    anime.isArchived.toggle()
                    anime.updatedAt = .now
                    actionToast = anime.isArchived ? .archived(title) : .unarchived(title)
                } label: {
                    Label(anime.isArchived ? "Unarchive" : "Archive",
                          systemImage: anime.isArchived ? "tray.and.arrow.up" : "archivebox")
                }
                .tint(anime.isArchived ? .blue : .orange)
            }
    }
}

// MARK: - Library Anime Row

struct LibraryAnimeRowView: View {
    let anime: AnimeShow

    private var nextEpisode: AnimeEpisode? { anime.nextUpcomingEpisode }
    private var backlogCount: Int { anime.backlogEpisodes.count }

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: anime.posterImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: "sparkles.tv")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                @unknown default:
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(anime.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text("Anime")
                        .statusBadge(color: .purple)
                }

                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .imageScale(.small)
                        .foregroundStyle(statusColor)
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }

                Text(anime.episodeProgress)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    private var statusIcon: String {
        if let ep = nextEpisode {
            return Calendar.current.isDateInToday(ep.airDate) ? "star.fill" : "calendar"
        }
        switch anime.animeStatus {
        case "FINISHED", "CANCELLED": return "checkmark.circle"
        case "NOT_YET_RELEASED": return "clock"
        case "HIATUS": return "pause.circle"
        default: return "tv"
        }
    }

    private var statusColor: Color {
        if let ep = nextEpisode {
            return Calendar.current.isDateInToday(ep.airDate) ? .orange : .secondary
        }
        return .secondary
    }

    private var statusLabel: String {
        if let ep = nextEpisode {
            if Calendar.current.isDateInToday(ep.airDate) { return "Ep \(ep.episodeNumber) airs today!" }
            return "Ep \(ep.episodeNumber) — \(ep.airDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        }
        switch anime.animeStatus {
        case "RELEASING":        return "On hiatus"
        case "FINISHED":         return "Finished — all caught up"
        case "CANCELLED":        return "Cancelled"
        case "NOT_YET_RELEASED": return "Coming soon"
        case "HIATUS":           return "On hiatus"
        default:                 return anime.animeStatus
        }
    }
}

// MARK: - Toast (generic, used across the app)

struct ToastView: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.toast))
        .lightShadow()
        .padding(.horizontal, 20)
    }
}

// MARK: - Added Toast (convenience wrapper)

struct AddedToastView: View {
    let showTitle: String
    var body: some View {
        ToastView(icon: "checkmark.circle.fill", iconColor: .green,
                  title: "Added to Library", subtitle: showTitle)
    }
}

// MARK: - Toast modifier (shows + auto-dismisses)

extension View {
    func toast(message: ToastMessage?, onDismiss: @escaping () -> Void) -> some View {
        self.overlay(alignment: .top) {
            if let msg = message {
                ToastView(icon: msg.icon, iconColor: msg.color, title: msg.title, subtitle: msg.subtitle)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeOut(duration: 0.3)) { onDismiss() }
                        }
                    }
                    .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.4), value: message?.id)
    }
}

struct ToastMessage: Equatable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    var subtitle: String? = nil

    static func added(_ name: String) -> ToastMessage {
        ToastMessage(icon: "checkmark.circle.fill", color: .green, title: "Added to Library", subtitle: name)
    }
    static func removed(_ name: String) -> ToastMessage {
        ToastMessage(icon: "trash.fill", color: .red, title: "Removed", subtitle: name)
    }
    static func watched(_ name: String) -> ToastMessage {
        ToastMessage(icon: "checkmark.circle.fill", color: .green, title: "Marked as Watched", subtitle: name)
    }
    static func unwatched(_ name: String) -> ToastMessage {
        ToastMessage(icon: "arrow.uturn.backward.circle.fill", color: .orange, title: "Marked as Unwatched", subtitle: name)
    }
    static func archived(_ name: String) -> ToastMessage {
        ToastMessage(icon: "archivebox.fill", color: .orange, title: "Archived", subtitle: name)
    }
    static func unarchived(_ name: String) -> ToastMessage {
        ToastMessage(icon: "tray.and.arrow.up.fill", color: .blue, title: "Unarchived", subtitle: name)
    }
}

// MARK: - Show Row

struct ShowRowView: View {
    let show: Show

    @AppStorage("preferredPlatforms") private var preferredPlatformsRaw: String = ""
    private var preferredPlatforms: Set<String> {
        Set(preferredPlatformsRaw.split(separator: ",").map(String.init))
    }

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
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                @unknown default:
                    Rectangle()
                        .foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

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

                // Provider signal — "Not in your lineup" if user has prefs and show isn't on any of them
                if !preferredPlatforms.isEmpty, !show.watchProviderNames.isEmpty {
                    let showPlatformRawValues = show.matchedStreamingPlatforms.map(\.rawValue)
                    let hasMatch = showPlatformRawValues.contains { preferredPlatforms.contains($0) }
                    if !hasMatch {
                        Text("Not in your lineup")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
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

    private var platformList: [String] {
        show.platforms.isEmpty ? [show.platform] : show.platforms
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(platformList.prefix(2), id: \.self) { p in
                Text(p)
                    .statusBadge(color: .secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .modelContainer(for: [Show.self, Episode.self, AnimeShow.self, AnimeEpisode.self], inMemory: true)
}
