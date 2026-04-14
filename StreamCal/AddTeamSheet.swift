import SwiftUI
import SwiftData

// MARK: - Unified Team Result

enum TeamResult: Identifiable {
    case tsdb(SDBTeam)
    case espn(ESPNTeam)

    var id: String {
        switch self {
        case .tsdb(let t): return "tsdb-\(t.idTeam)"
        case .espn(let t): return "espn-\(t.id)"
        }
    }

    var name: String {
        switch self { case .tsdb(let t): return t.strTeam; case .espn(let t): return t.displayName }
    }
    var league: String {
        switch self {
        case .tsdb(let t): return t.strLeague ?? t.strSport
        case .espn(let t): return t.league
        }
    }
    var sport: String {
        switch self { case .tsdb(let t): return t.strSport; case .espn(let t): return t.league }
    }
    var country: String? {
        switch self { case .tsdb(let t): return t.strCountry; case .espn: return "USA" }
    }
    var logoURL: URL? {
        switch self {
        case .tsdb(let t): return t.strTeamBadge.flatMap { URL(string: $0) }
        case .espn(let t): return t.logoURL
        }
    }
    /// The native ID used to detect duplicates (stored in SportTeam.sportsDBID regardless of source).
    var nativeID: String {
        switch self { case .tsdb(let t): return t.idTeam; case .espn(let t): return t.id }
    }
}

// MARK: - Sheet

struct AddTeamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var onAdded: ((String) -> Void)? = nil

    @State private var searchText = ""
    @State private var results: [TeamResult] = []
    @State private var browsingLeague: ESPNLeagueConfig? = nil
    @State private var isSearching = false
    @State private var isLoadingLeague = false
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var libraryTeamIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if isImporting {
                    importingRow
                } else if let error = importError {
                    errorRow(error)
                } else if isSearching || isLoadingLeague {
                    EmptyView() // overlay spinner handles this
                } else if results.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if results.isEmpty && searchText.isEmpty {
                    leagueBrowser
                } else {
                    // Browse or search results
                    if let league = browsingLeague, searchText.isEmpty {
                        Section {
                            Button {
                                browsingLeague = nil
                                results = []
                            } label: {
                                Label("Browse other leagues", systemImage: "chevron.left")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                    resultRows
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
                if isSearching || isLoadingLeague { ProgressView() }
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

    // MARK: - Sub-views

    private var importingRow: some View {
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
    }

    private func errorRow(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Import failed", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var leagueBrowser: some View {
        Section("Browse by League") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ESPNService.leagues, id: \.name) { config in
                    Button {
                        Task { await loadLeague(config) }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: config.icon)
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            Text(config.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }

        Section {
            Text("For soccer teams, search by name above — Arsenal, Real Madrid, Barcelona, etc.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var resultRows: some View {
        // When browsing a league (not searching), hide already-added teams entirely.
        // When searching, show them with a checkmark so users know they're tracked.
        let displayResults = (browsingLeague != nil && searchText.isEmpty)
            ? results.filter { !libraryTeamIDs.contains($0.nativeID) }
            : results
        ForEach(displayResults) { result in
            let alreadyAdded = libraryTeamIDs.contains(result.nativeID)
            Button {
                guard !alreadyAdded else { return }
                Task { await importResult(result) }
            } label: {
                UnifiedTeamResultRow(result: result, alreadyAdded: alreadyAdded)
            }
            .buttonStyle(.plain)
            .disabled(alreadyAdded)
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
        browsingLeague = nil
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
            async let tsdbResults = TheSportsDBService.shared.searchTeams(query: trimmed)
            async let espnResults = ESPNService.shared.searchTeams(query: trimmed)
            let tsdb = (try? await tsdbResults) ?? []
            let espn = (try? await espnResults) ?? []
            let combined = tsdb.map { TeamResult.tsdb($0) } + espn.map { TeamResult.espn($0) }
            if !Task.isCancelled { results = combined }
            isSearching = false
        }
    }

    private func loadLeague(_ config: ESPNLeagueConfig) async {
        isLoadingLeague = true
        let teams = (try? await ESPNService.shared.fetchTeams(for: config)) ?? []
        results = teams.map { .espn($0) }
        browsingLeague = config
        isLoadingLeague = false
    }

    // MARK: - Import

    private func importResult(_ result: TeamResult) async {
        switch result {
        case .tsdb(let team): await importTSDBTeam(team)
        case .espn(let team): await importESPNTeam(team)
        }
    }

    private func importTSDBTeam(_ sdbTeam: SDBTeam) async {
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
                badgeURL: sdbTeam.strTeamBadge,
                dataSource: "tsdb"
            )
            modelContext.insert(team)
            try? modelContext.save()

            let events = try await TheSportsDBService.shared.fetchNextEvents(teamID: sdbTeam.idTeam)
            upsertTSDBGames(events, for: team)
            try? modelContext.save()

            await NotificationService.shared.scheduleNotifications(for: team)
            let name = team.name
            dismiss()
            onAdded?(name)
        } catch {
            importError = error.localizedDescription
            isImporting = false
        }
    }

    private func importESPNTeam(_ espnTeam: ESPNTeam) async {
        isImporting = true
        importError = nil
        do {
            // Store ESPN ID in sportsDBID; use leagueID for the "sport/league" path
            let team = SportTeam(
                name: espnTeam.displayName,
                sportsDBID: espnTeam.id,
                sport: espnTeam.league,
                league: espnTeam.league,
                leagueID: espnTeam.leaguePath,  // e.g. "football/nfl" for refresh routing
                country: "USA",
                badgeURL: espnTeam.logoURL?.absoluteString,
                dataSource: "espn"
            )
            modelContext.insert(team)
            try? modelContext.save()

            let events = try await ESPNService.shared.fetchSchedule(
                espnTeamID: espnTeam.id,
                sport: espnTeam.sport,
                leaguePath: espnTeam.leaguePath
            )
            upsertESPNGames(events, for: team)
            try? modelContext.save()

            await NotificationService.shared.scheduleNotifications(for: team)
            let name = team.name
            dismiss()
            onAdded?(name)
        } catch {
            importError = error.localizedDescription
            isImporting = false
        }
    }

    private func upsertTSDBGames(_ events: [SDBEvent], for team: SportTeam) {
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

    private func upsertESPNGames(_ events: [ESPNEvent], for team: SportTeam) {
        for event in events {
            let comp = event.competitions.first
            let home = comp?.competitors.first(where: { $0.homeAway == "home" })?.team.displayName ?? ""
            let away = comp?.competitors.first(where: { $0.homeAway == "away" })?.team.displayName ?? ""
            let isCompleted = comp?.status?.type?.completed ?? false

            var result: String? = nil
            if isCompleted,
               let homeScore = comp?.competitors.first(where: { $0.homeAway == "home" })?.score?.value,
               let awayScore = comp?.competitors.first(where: { $0.homeAway == "away" })?.score?.value {
                result = "\(Int(homeScore))–\(Int(awayScore))"
            }

            let game = SportGame(
                sportsDBEventID: event.id,
                title: event.name,
                homeTeam: home,
                awayTeam: away,
                gameDate: event.parsedDate ?? .distantFuture,
                venue: comp?.venue?.fullName,
                result: result,
                isCompleted: isCompleted
            )
            game.team = team
            modelContext.insert(game)
        }
    }
}

// MARK: - Unified Result Row

struct UnifiedTeamResultRow: View {
    let result: TeamResult
    let alreadyAdded: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: result.logoURL) { phase in
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
                    RoundedRectangle(cornerRadius: 6).foregroundStyle(Color(.systemGray5))
                }
            }
            .frame(width: 46, height: 46)
            .opacity(alreadyAdded ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(alreadyAdded ? .secondary : .primary)
                HStack(spacing: 4) {
                    Text(result.league)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let country = result.country {
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
