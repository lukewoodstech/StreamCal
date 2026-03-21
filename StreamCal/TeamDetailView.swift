import SwiftUI
import SwiftData

struct TeamDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let team: SportTeam
    var onDeleted: ((String) -> Void)? = nil

    private var upcoming: [SportGame] {
        team.games
            .filter { !$0.isCompleted }
            .sorted { $0.gameDate < $1.gameDate }
    }

    private var results: [SportGame] {
        team.games
            .filter { $0.isCompleted }
            .sorted { $0.gameDate > $1.gameDate }
    }

    var body: some View {
        List {
            // Team header
            Section {
                HStack(spacing: 14) {
                    CachedAsyncImage(url: team.badgeImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                        case .failure, .empty:
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .foregroundStyle(DS.Color.imagePlaceholder)
                                .overlay {
                                    Image(systemName: "sportscourt")
                                        .foregroundStyle(.tertiary)
                                }
                        @unknown default:
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .foregroundStyle(DS.Color.imagePlaceholder)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(team.league)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let country = team.country {
                            Text(country)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        HStack(spacing: 6) {
                            Text("\(team.games.filter { !$0.isCompleted }.count) upcoming")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                                .font(.caption2)
                            Text("\(results.count) results")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { game in
                        GameRowView(game: game, team: team)
                    }
                }
            }

            if !results.isEmpty {
                Section("Results") {
                    ForEach(results) { game in
                        GameRowView(game: game, team: team)
                    }
                }
            }

            if upcoming.isEmpty && results.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Games",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No schedule data available.")
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        team.notificationsEnabled.toggle()
                    } label: {
                        Label(
                            team.notificationsEnabled ? "Mute Notifications" : "Unmute Notifications",
                            systemImage: team.notificationsEnabled ? "bell.slash" : "bell"
                        )
                    }
                    Divider()
                    Button(role: .destructive) {
                        let name = team.name
                        modelContext.delete(team)
                        dismiss()
                        onDeleted?(name)
                    } label: {
                        Label("Remove Team", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable {
            await RefreshService.shared.refreshTeam(team, modelContext: modelContext)
        }
    }
}

#Preview {
    NavigationStack {
        TeamDetailView(team: SportTeam(
            name: "Manchester City",
            sportsDBID: "133613",
            sport: "Soccer",
            league: "English Premier League",
            leagueID: "4328"
        ))
    }
    .modelContainer(for: [SportTeam.self, SportGame.self], inMemory: true)
}
