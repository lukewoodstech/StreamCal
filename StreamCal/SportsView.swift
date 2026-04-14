import SwiftUI
import SwiftData

struct SportsView: View {

    var searchText: String = ""
    var onAdd: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SportTeam.name)
    private var teams: [SportTeam]

    @State private var toast: ToastMessage? = nil

    private var isSearching: Bool { !searchText.isEmpty }

    private var filteredTeams: [SportTeam] {
        let q = searchText.lowercased()
        return teams.filter { $0.name.lowercased().contains(q) || $0.league.lowercased().contains(q) }
    }

    private let sportOrder = ["Football", "Basketball", "Baseball", "Hockey", "Soccer", "Racing", "Other"]

    /// Normalizes raw stored sport values (ESPN slugs, TSDB strings, league names) to a consistent display label.
    private func normalizedSport(_ raw: String) -> String {
        switch raw.lowercased() {
        case "football", "nfl", "ncaa football", "american football": return "Football"
        case "basketball", "nba", "wnba", "ncaa basketball", "mens-college-basketball": return "Basketball"
        case "baseball", "mlb": return "Baseball"
        case "hockey", "nhl", "ice hockey": return "Hockey"
        case "soccer", "mls", "usa.1": return "Soccer"
        case "racing", "motorsport", "f1", "nascar cup": return "Racing"
        default: return raw
        }
    }

    private var teamsBySport: [(sport: String, teams: [SportTeam])] {
        let grouped = Dictionary(grouping: teams) { normalizedSport($0.sport) }
        return grouped
            .map { (sport: $0.key, teams: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                let li = sportOrder.firstIndex(of: lhs.sport) ?? Int.max
                let ri = sportOrder.firstIndex(of: rhs.sport) ?? Int.max
                return li == ri ? lhs.sport < rhs.sport : li < ri
            }
    }

    var body: some View {
        Group {
            if isSearching {
                if filteredTeams.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    let filteredBySport: [(sport: String, teams: [SportTeam])] = {
                        let grouped = Dictionary(grouping: filteredTeams) { normalizedSport($0.sport) }
                        return grouped
                            .map { (sport: $0.key, teams: $0.value.sorted { $0.name < $1.name }) }
                            .sorted { lhs, rhs in
                                let li = sportOrder.firstIndex(of: lhs.sport) ?? Int.max
                                let ri = sportOrder.firstIndex(of: rhs.sport) ?? Int.max
                                return li == ri ? lhs.sport < rhs.sport : li < ri
                            }
                    }()
                    List {
                        ForEach(filteredBySport, id: \.sport) { group in
                            Section(group.sport) {
                                ForEach(group.teams) { team in
                                    NavigationLink(destination: TeamDetailView(team: team, onDeleted: { name in toast = .removed(name) })) {
                                        TeamRowView(team: team)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            let name = team.name
                                            modelContext.delete(team)
                                            toast = .removed(name)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            } else if teams.isEmpty {
                ContentUnavailableView {
                    Label("No Teams Yet", systemImage: "sportscourt.fill")
                } description: {
                    Text("Follow a team to see their upcoming games.")
                } actions: {
                    Button("Add a Team") { onAdd?() }
                        .buttonStyle(.bordered)
                }
            } else {
                List {
                    ForEach(teamsBySport, id: \.sport) { group in
                        Section(group.sport) {
                            ForEach(group.teams) { team in
                                NavigationLink(destination: TeamDetailView(team: team, onDeleted: { name in toast = .removed(name) })) {
                                    TeamRowView(team: team)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        let name = team.name
                                        modelContext.delete(team)
                                        toast = .removed(name)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await RefreshService.shared.refreshAllTeams(modelContext: modelContext)
                }
            }
        }
        .toast(message: toast) { toast = nil }
    }
}

// MARK: - Team Row

struct TeamRowView: View {
    let team: SportTeam

    private var upcomingGames: [SportGame] {
        let now = Date.now
        return team.games
            .filter { !$0.isCompleted && $0.gameDate > now }
            .sorted { $0.gameDate < $1.gameDate }
    }

    private var nextGame: SportGame? { upcomingGames.first }

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: team.badgeImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: "sportscourt")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                @unknown default:
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(team.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(team.league).statusBadge(color: .secondary)
                }

                if let game = nextGame {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                        Text(game.displayTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(game.gameDate, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("No upcoming games")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Game Row (reused in TeamDetailView)

struct GameRowView: View {
    let game: SportGame
    var team: SportTeam? = nil

    /// Badge URL for the home team (only available when the tracked team is playing at home)
    private var homeBadgeURL: URL? {
        guard let team, game.homeTeam == team.name else { return nil }
        return team.badgeImageURL
    }

    var body: some View {
        HStack(spacing: 10) {
            // Home team badge or placeholder
            Group {
                if let url = homeBadgeURL {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                        default:
                            Image(systemName: "house.fill")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.xs)
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: game.homeTeam == (team?.name ?? "") ? "house.fill" : "house")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))

        VStack(alignment: .leading, spacing: 6) {
            Text(game.displayTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            HStack(spacing: 12) {
                if game.isCompleted {
                    if let result = game.result {
                        Text(result)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    Text("Final")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "calendar")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    if game.gameDate == .distantFuture {
                        Text("TBA")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(game.gameDate, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(game.formattedGameTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let venue = game.venue {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                if let round = game.round {
                    Text(round)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let network = game.broadcastNetwork {
                    Text(network)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
        } // VStack
        } // HStack
        .padding(.vertical, 2)
        .opacity(game.isCompleted ? 0.7 : 1)
    }
}

#Preview {
    NavigationStack {
        SportsView()
    }
    .modelContainer(for: [SportTeam.self, SportGame.self], inMemory: true)
}
