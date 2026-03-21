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
    @State private var actionToast: ToastMessage? = nil

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
                                            let title = show.title
                                            modelContext.delete(show)
                                            actionToast = .removed(title)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            let title = show.title
                                            show.isArchived = true
                                            show.updatedAt = .now
                                            actionToast = .archived(title)
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
                                            let title = show.title
                                            modelContext.delete(show)
                                            actionToast = .removed(title)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            let title = show.title
                                            show.isArchived = true
                                            show.updatedAt = .now
                                            actionToast = .archived(title)
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
                                            let title = show.title
                                            modelContext.delete(show)
                                            actionToast = .removed(title)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            let title = show.title
                                            show.isArchived = false
                                            show.updatedAt = .now
                                            actionToast = .unarchived(title)
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
            .toast(message: addedShowTitle.map { .added($0) } ?? actionToast) {
                addedShowTitle = nil
                actionToast = nil
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
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
