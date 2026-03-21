import SwiftUI
import SwiftData

struct AddTeamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var onAdded: ((String) -> Void)? = nil

    @State private var searchText = ""
    @State private var results: [SDBTeam] = []
    @State private var isSearching = false
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var libraryTeamIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if isImporting {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Adding team…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 40)
                } else if let error = importError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Import failed", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if results.isEmpty && !searchText.isEmpty && !isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(results) { team in
                        let alreadyAdded = libraryTeamIDs.contains(team.idTeam)
                        Button {
                            guard !alreadyAdded else { return }
                            Task { await importTeam(team) }
                        } label: {
                            TeamSearchResultRow(team: team, alreadyAdded: alreadyAdded)
                        }
                        .buttonStyle(.plain)
                        .disabled(alreadyAdded)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search teams…"
            )
            .onChange(of: searchText) { _, newValue in scheduleSearch(query: newValue) }
            .overlay {
                if isSearching { ProgressView() }
            }
            .navigationTitle("Add Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { loadLibraryIDs() }
        }
    }

    // MARK: - Search

    private func loadLibraryIDs() {
        let descriptor = FetchDescriptor<SportTeam>()
        if let teams = try? modelContext.fetch(descriptor) {
            libraryTeamIDs = Set(teams.map { $0.sportsDBID })
        }
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            isSearching = true
            do {
                let found = try await TheSportsDBService.shared.searchTeams(query: trimmed)
                if !Task.isCancelled { results = found }
            } catch {
                if !Task.isCancelled { results = [] }
            }
            isSearching = false
        }
    }

    // MARK: - Import

    private func importTeam(_ sdbTeam: SDBTeam) async {
        isImporting = true
        importError = nil
        do {
            let team = SportTeam(
                name: sdbTeam.strTeam,
                sportsDBID: sdbTeam.idTeam,
                sport: sdbTeam.strSport,
                league: sdbTeam.strLeague ?? sdbTeam.strSport,
                leagueID: sdbTeam.idLeague,
                country: sdbTeam.strCountry,
                badgeURL: sdbTeam.strTeamBadge
            )
            modelContext.insert(team)
            try? modelContext.save()

            // Fetch upcoming events
            let events = try await TheSportsDBService.shared.fetchNextEvents(teamID: sdbTeam.idTeam)
            upsertGames(events, for: team)
            try? modelContext.save()

            // Schedule game notifications
            await NotificationService.shared.scheduleNotifications(for: team)

            let name = team.name
            dismiss()
            onAdded?(name)
        } catch {
            importError = error.localizedDescription
            isImporting = false
        }
    }

    private func upsertGames(_ events: [SDBEvent], for team: SportTeam) {
        for event in events {
            let game = SportGame(
                sportsDBEventID: event.idEvent,
                title: event.strEvent,
                homeTeam: event.strHomeTeam ?? "",
                awayTeam: event.strAwayTeam ?? "",
                gameDate: event.parsedGameDate ?? .distantFuture,
                venue: event.strVenue,
                round: event.strRound,
                season: event.strSeason,
                result: event.result,
                isCompleted: event.isCompleted
            )
            game.team = team
            modelContext.insert(game)
        }
    }
}

// MARK: - Search Result Row

struct TeamSearchResultRow: View {
    let team: SDBTeam
    let alreadyAdded: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: team.strTeamBadge.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: 6)
                        .foregroundStyle(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "sportscourt")
                                .foregroundStyle(.tertiary)
                        }
                @unknown default:
                    RoundedRectangle(cornerRadius: 6)
                        .foregroundStyle(Color(.systemGray5))
                }
            }
            .frame(width: 46, height: 46)
            .opacity(alreadyAdded ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(team.strTeam)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(alreadyAdded ? .secondary : .primary)
                HStack(spacing: 4) {
                    Text(team.strSport)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let league = team.strLeague {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(league)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let country = team.strCountry {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(country)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if alreadyAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.large)
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accentColor)
                    .imageScale(.large)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AddTeamSheet()
        .modelContainer(for: [SportTeam.self, SportGame.self], inMemory: true)
}
