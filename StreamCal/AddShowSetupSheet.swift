import SwiftUI
import SwiftData

/// Presented immediately after a show is imported from TMDB when it has aired episodes.
/// Lets the user tell the app where they are in the show so the watch state is correct
/// from day one — avoiding a dumped backlog.
struct AddShowSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let show: Show

    // Season/episode picker state
    @State private var selectedSeason: Int = 1
    @State private var selectedEpisode: Int = 1
    @State private var showingEpisodePicker = false

    private var airedEpisodes: [Episode] {
        let today = Calendar.current.startOfDay(for: .now)
        return show.sortedEpisodes.filter {
            $0.airDate <= today && $0.airDate != .distantFuture
        }
    }

    private var availableSeasons: [Int] {
        Array(Set(airedEpisodes.map { $0.seasonNumber })).sorted()
    }

    private func episodes(for season: Int) -> [Episode] {
        airedEpisodes.filter { $0.seasonNumber == season }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                posterHeader

                List {
                    Section {
                        Text("StreamCal needs to know where you are in \(show.title) so it can show the right episodes going forward.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                    }

                    Section {
                        Button {
                            markAllAiredWatched()
                        } label: {
                            SetupOptionRow(
                                icon: "checkmark.circle.fill",
                                iconColor: .green,
                                title: "I'm all caught up",
                                subtitle: "Mark all \(airedEpisodes.count) aired episodes as watched"
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingEpisodePicker = true
                        } label: {
                            SetupOptionRow(
                                icon: "play.circle.fill",
                                iconColor: .blue,
                                title: "I'm partway through",
                                subtitle: "Choose the last episode you watched"
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            startFromBeginning()
                        } label: {
                            SetupOptionRow(
                                icon: "arrow.counterclockwise.circle.fill",
                                iconColor: .orange,
                                title: "Starting from the beginning",
                                subtitle: "Keep all episodes as unwatched"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Where are you?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingEpisodePicker) {
                EpisodePickerSheet(
                    show: show,
                    airedEpisodes: airedEpisodes,
                    availableSeasons: availableSeasons,
                    selectedSeason: $selectedSeason,
                    selectedEpisode: $selectedEpisode
                ) { season, episode in
                    markWatchedUpTo(season: season, episode: episode)
                }
            }
            .onAppear {
                // Pre-select the last aired episode as a sensible default
                if let last = airedEpisodes.last {
                    selectedSeason = last.seasonNumber
                    selectedEpisode = last.episodeNumber
                }
            }
        }
    }

    // MARK: - Poster header

    @ViewBuilder
    private var posterHeader: some View {
        if let urlString = show.posterURL, let url = URL(string: urlString) {
            HStack(spacing: 16) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        Rectangle().foregroundStyle(Color(.systemGray5))
                    @unknown default:
                        Rectangle().foregroundStyle(Color(.systemGray5))
                    }
                }
                .frame(width: 56, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(show.title)
                        .font(.headline)
                    Text("\(airedEpisodes.count) episodes aired")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PlatformBadge(platform: show.platform)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Actions

    private func markAllAiredWatched() {
        for ep in airedEpisodes { ep.isWatched = true }
        Task { await NotificationService.shared.scheduleNotifications(for: show) }
        dismiss()
    }

    private func startFromBeginning() {
        dismiss()
    }

    private func markWatchedUpTo(season: Int, episode: Int) {
        for ep in airedEpisodes {
            if ep.seasonNumber < season {
                ep.isWatched = true
            } else if ep.seasonNumber == season && ep.episodeNumber <= episode {
                ep.isWatched = true
            }
        }
        Task { await NotificationService.shared.scheduleNotifications(for: show) }
        dismiss()
    }
}

// MARK: - Setup Option Row

private struct SetupOptionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Episode Picker Sheet

private struct EpisodePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let show: Show
    let airedEpisodes: [Episode]
    let availableSeasons: [Int]
    @Binding var selectedSeason: Int
    @Binding var selectedEpisode: Int
    let onConfirm: (Int, Int) -> Void

    private var episodesInSelectedSeason: [Episode] {
        airedEpisodes.filter { $0.seasonNumber == selectedSeason }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Season") {
                    Picker("Season", selection: $selectedSeason) {
                        ForEach(availableSeasons, id: \.self) { s in
                            Text("Season \(s)").tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .onChange(of: selectedSeason) { _, _ in
                        // Reset episode to last in new season
                        if let last = episodesInSelectedSeason.last {
                            selectedEpisode = last.episodeNumber
                        }
                    }
                }

                Section("Last episode watched") {
                    Picker("Episode", selection: $selectedEpisode) {
                        ForEach(episodesInSelectedSeason) { ep in
                            Text("E\(ep.episodeNumber)\(ep.title.isEmpty ? "" : " — \(ep.title)")")
                                .tag(ep.episodeNumber)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                Section {
                    Text("Everything up to and including S\(String(format: "%02d", selectedSeason))E\(String(format: "%02d", selectedEpisode)) will be marked as watched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Pick your progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Confirm") {
                        onConfirm(selectedSeason, selectedEpisode)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    AddShowSetupSheetPreview()
}

private struct AddShowSetupSheetPreview: View {
    var body: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Show.self, Episode.self, configurations: config)
        let ctx = container.mainContext
        let show = Show(title: "Severance", platform: "Apple TV+",
                        posterURL: nil, showStatus: "Returning Series")
        ctx.insert(show)
        for i in 1...8 {
            let ep = Episode(seasonNumber: 1, episodeNumber: i, title: "Episode \(i)",
                             airDate: Calendar.current.date(byAdding: .day, value: -(30 - i * 3), to: .now)!)
            ep.show = show
            ctx.insert(ep)
        }
        return AddShowSetupSheet(show: show)
            .modelContainer(container)
    }
}
