import SwiftUI
import SwiftData

struct TeamDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let team: SportTeam
    var onDeleted: ((String) -> Void)? = nil

    private var upcoming: [SportGame] {
        team.games
            .filter { !$0.isCompleted && $0.gameDate >= .now }
            .sorted { $0.gameDate < $1.gameDate }
    }

    private var recentResults: [SportGame] {
        team.games
            .filter { $0.isCompleted }
            .sorted { $0.gameDate > $1.gameDate }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                teamHeader
                    .padding(.bottom, DS.Spacing.lg)

                if let next = upcoming.first {
                    nextGameCard(next)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.lg)
                }

                let remainingUpcoming = upcoming.count > 1 ? Array(upcoming.dropFirst()) : []
                if !remainingUpcoming.isEmpty {
                    scheduleSection(remainingUpcoming)
                        .padding(.bottom, DS.Spacing.lg)
                }

                if upcoming.isEmpty {
                    noGamesCard
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.lg)
                }

                if !recentResults.isEmpty {
                    resultsSection
                        .padding(.bottom, DS.Spacing.xl)
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
                        if team.notificationsEnabled {
                            Task { await NotificationService.shared.scheduleNotifications(for: team) }
                        } else {
                            NotificationService.shared.cancelGameNotifications(for: team)
                        }
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
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .refreshable {
            await RefreshService.shared.refreshTeam(team, modelContext: modelContext)
        }
    }

    // MARK: - Team Header

    private var teamHeader: some View {
        VStack(spacing: DS.Spacing.sm) {
            CachedAsyncImage(url: team.badgeImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .foregroundStyle(DS.Color.imagePlaceholder)
                        .overlay {
                            Image(systemName: "sportscourt")
                                .font(.title)
                                .foregroundStyle(.tertiary)
                        }
                @unknown default:
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .foregroundStyle(DS.Color.imagePlaceholder)
                }
            }
            .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text(team.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                HStack(spacing: 4) {
                    Text(team.league)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let country = team.country, !country.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                            .font(.subheadline)
                        Text(country)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.lg)
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Next Game Card

    private func nextGameCard(_ game: SportGame) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Next Game", systemImage: "calendar.badge.clock")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                Text(opponent(for: game))
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if game.gameDate == .distantFuture {
                        Text("Date TBA")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(game.gameDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(game.gameDate.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let venue = game.venue, !venue.isEmpty {
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if game.gameDate != .distantFuture {
                    let label = countdownLabel(for: game.gameDate)
                    if !label.isEmpty {
                        Text(label)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Calendar.current.isDateInToday(game.gameDate) ? .orange : Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (Calendar.current.isDateInToday(game.gameDate) ? Color.orange : Color.accentColor).opacity(0.12)
                            )
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Schedule

    private func scheduleSection(_ games: [SportGame]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Schedule")
                .font(.headline)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.sm)

            VStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.persistentModelID) { index, game in
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opponent(for: game))
                                    .font(.subheadline)
                                    .lineLimit(1)
                                if let round = game.round {
                                    Text(round)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if game.gameDate == .distantFuture {
                                    Text("TBA")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                } else {
                                    Text(game.gameDate.formatted(.dateTime.month(.abbreviated).day()))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(game.gameDate.formatted(.dateTime.hour().minute()))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, 11)

                        if index < games.count - 1 {
                            Divider().padding(.leading, DS.Spacing.lg)
                        }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Results")
                .font(.headline)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.sm)

            VStack(spacing: 0) {
                ForEach(Array(recentResults.enumerated()), id: \.element.persistentModelID) { index, game in
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opponent(for: game))
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(game.gameDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if let result = game.result {
                                let outcome = gameOutcome(game: game, result: result)
                                HStack(spacing: 6) {
                                    Text(result)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(outcome.label)
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(outcome.color)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, 11)

                        if index < recentResults.count - 1 {
                            Divider().padding(.leading, DS.Spacing.lg)
                        }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - No Games

    private var noGamesCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.secondary)
            Text("No upcoming games scheduled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Helpers

    private func opponent(for game: SportGame) -> String {
        if game.homeTeam == team.name {
            return "vs \(game.awayTeam)"
        } else if game.awayTeam == team.name {
            return "at \(game.homeTeam)"
        }
        return game.title
    }

    private func countdownLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
        if days > 0 { return "In \(days) days" }
        return ""
    }

    private func gameOutcome(game: SportGame, result: String) -> (label: String, color: Color) {
        // Try to parse "homeScore–awayScore" or "awayScore–homeScore"
        let parts = result.components(separatedBy: ["–", "-"]).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return ("?", .secondary) }

        let isHome = game.homeTeam == team.name
        let teamScore = isHome ? parts[0] : parts[1]
        let oppScore  = isHome ? parts[1] : parts[0]

        if teamScore > oppScore  { return ("W", .green) }
        if teamScore < oppScore  { return ("L", .red) }
        return ("D", .secondary)
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
