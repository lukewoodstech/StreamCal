import SwiftUI
import SwiftData

struct LibraryView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Show.createdAt, order: .reverse)
    private var shows: [Show]

    @State private var showingAddShow = false
    @State private var addedShowTitle: String? = nil

    var activeShows: [Show] { shows.filter { !$0.isArchived } }
    var archivedShows: [Show] { shows.filter { $0.isArchived } }

    var body: some View {
        NavigationStack {
            Group {
                if shows.isEmpty {
                    ContentUnavailableView(
                        "No Shows Yet",
                        systemImage: "rectangle.stack.fill",
                        description: Text("Tap + to add your first show.")
                    )
                } else {
                    List {
                        if !activeShows.isEmpty {
                            Section("Following") {
                                ForEach(activeShows) { show in
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
            .navigationTitle("Library")
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
            AsyncImage(url: posterURL) { phase in
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
                    Spacer()
                    PlatformBadge(platform: show.platform)
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
        if progress.plannedToday != nil { return "moon.stars.fill" }
        if progress.hasBacklog { return "play.circle.fill" }
        if progress.isFullyCaughtUp { return "checkmark.circle.fill" }
        if progress.nextUpcoming != nil { return "calendar" }
        return "tv"
    }

    private var progressColor: Color {
        if progress.plannedToday != nil { return .indigo }
        if progress.hasBacklog { return .blue }
        if progress.isFullyCaughtUp { return .green }
        if let upcoming = progress.nextUpcoming,
           Calendar.current.isDateInToday(upcoming.airDate) { return .orange }
        return .secondary
    }
}

struct PlatformBadge: View {
    let platform: String

    var body: some View {
        Text(platform)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(platformColor.opacity(0.15))
            .foregroundStyle(platformColor)
            .clipShape(Capsule())
    }

    private var platformColor: Color {
        switch platform {
        case StreamingPlatform.netflix.rawValue: return .red
        case StreamingPlatform.disneyPlus.rawValue: return .blue
        case StreamingPlatform.hulu.rawValue: return .green
        case StreamingPlatform.max.rawValue: return .purple
        case StreamingPlatform.appleTV.rawValue: return .primary
        case StreamingPlatform.amazonPrime.rawValue: return .cyan
        case StreamingPlatform.peacock.rawValue: return .indigo
        case StreamingPlatform.paramountPlus.rawValue: return .teal
        default: return .secondary
        }
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
