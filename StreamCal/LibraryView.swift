import SwiftUI
import SwiftData

struct LibraryView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Show.createdAt, order: .reverse)
    private var shows: [Show]

    @State private var showingAddShow = false

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
                AddShowSheet()
            }
        }
    }
}

struct ShowRowView: View {
    let show: Show

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
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(show.title)
                        .font(.headline)
                    Spacer()
                    PlatformBadge(platform: show.platform)
                }
                if let dateText = show.nextEpisodeDateText {
                    Label(dateText, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No upcoming episodes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
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
