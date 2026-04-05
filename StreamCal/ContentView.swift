import SwiftUI
import SwiftData

enum LibraryContentType: String, CaseIterable {
    case shows = "Shows"
    case movies = "Movies"
    case sports = "Sports"
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab: Int = 0

    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingView()
        } else {
            ZStack {
                CalendarView()
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)
                LibraryContainerView()
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
                NextUpView()
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)
                SettingsView()
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 3)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingTabBar(selectedTab: $selectedTab)
            }
        }
    }
}

// MARK: - Library Container

struct LibraryContainerView: View {
    @State private var contentType: LibraryContentType = .shows
    @State private var showingAdd = false
    @State private var addedTitle: String? = nil
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                switch contentType {
                case .shows:   LibraryView(standalone: false, searchText: searchText, onAdd: { showingAdd = true })
                case .movies:  MoviesView(searchText: searchText, onAdd: { showingAdd = true })
                case .sports:  SportsView(searchText: searchText, onAdd: { showingAdd = true })
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        Text("Library")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { showingAdd = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    Picker("Content Type", selection: $contentType) {
                        ForEach(LibraryContentType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .onChange(of: contentType) { _, _ in searchText = "" }

                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tertiary)
                        TextField("Search", text: $searchText)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                    Divider()
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .sheet(isPresented: $showingAdd) {
                switch contentType {
                case .shows:  AddShowSheet(onAdded: { title in addedTitle = title })
                case .movies: AddMovieSheet(onAdded: { title in addedTitle = title })
                case .sports: AddTeamSheet(onAdded: { name in addedTitle = name })
                }
            }
            .toast(message: addedTitle.map { .added($0) }) { addedTitle = nil }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Show.self, Episode.self, Movie.self, SportTeam.self, SportGame.self, AnimeShow.self, AnimeEpisode.self], inMemory: true)

}
