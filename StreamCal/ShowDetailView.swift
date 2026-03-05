import SwiftUI
import SwiftData

struct ShowDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let show: Show

    @State private var showingEditShow = false
    @State private var showingAddEpisode = false

    var body: some View {
        List {
            showInfoSection
            episodesSection
        }
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Show") { showingEditShow = true }
                    Button(show.isArchived ? "Unarchive" : "Archive") {
                        show.isArchived.toggle()
                        show.updatedAt = .now
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditShow) {
            AddShowSheet(existingShow: show)
        }
        .sheet(isPresented: $showingAddEpisode) {
            AddEpisodeSheet(show: show)
        }
    }

    private var showInfoSection: some View {
        Section {
            LabeledContent("Platform") {
                PlatformBadge(platform: show.platform)
            }
            if !show.notes.isEmpty {
                Text(show.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if show.isArchived {
                Label("Archived", systemImage: "archivebox")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Info")
        }
    }

    private var episodesSection: some View {
        Section {
            if show.sortedEpisodes.isEmpty {
                Text("No episodes yet.")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(show.sortedEpisodes) { episode in
                    EpisodeRowView(episode: episode)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(episode)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                episode.isWatched.toggle()
                            } label: {
                                Label(
                                    episode.isWatched ? "Unwatch" : "Watched",
                                    systemImage: episode.isWatched ? "eye.slash" : "checkmark"
                                )
                            }
                            .tint(episode.isWatched ? .gray : .green)
                        }
                }
            }
        } header: {
            HStack {
                Text("Episodes")
                Spacer()
                Button {
                    showingAddEpisode = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }
}

struct EpisodeRowView: View {
    let episode: Episode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(episode.isWatched ? .secondary : .primary)
                Text(episode.airDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if episode.isWatched {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

#Preview {
    ShowDetailPreviewWrapper()
}

private struct ShowDetailPreviewWrapper: View {
    var body: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Show.self, Episode.self, configurations: config)
        let show = Show(title: "Severance", platform: "Apple TV+", notes: "Great thriller")
        container.mainContext.insert(show)
        let ep1 = Episode(seasonNumber: 2, episodeNumber: 1, title: "Goodbye, Mrs. Selvig",
                          airDate: Calendar.current.date(byAdding: .day, value: 3, to: .now)!)
        ep1.show = show
        container.mainContext.insert(ep1)
        let ep2 = Episode(seasonNumber: 2, episodeNumber: 2, title: "Famine, Flood, and Fire",
                          airDate: Calendar.current.date(byAdding: .day, value: 10, to: .now)!,
                          isWatched: false)
        ep2.show = show
        container.mainContext.insert(ep2)
        return NavigationStack {
            ShowDetailView(show: show)
        }
        .modelContainer(container)
    }
}
