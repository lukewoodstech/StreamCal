import SwiftUI
import SwiftData

enum LibraryContentType: String, CaseIterable {
    case shows = "Shows"
    case movies = "Movies"
    case sports = "Sports"
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingView()
        } else {
        TabView {
            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            NextUpView()
                .tabItem {
                    Label("Next Up", systemImage: "play.circle.fill")
                }

            LibraryContainerView()
                .tabItem {
                    Label("Library", systemImage: "rectangle.stack.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        } // end onboarding check
    }
}

// MARK: - Library Container

struct LibraryContainerView: View {
    @State private var contentType: LibraryContentType = .shows
    @State private var showingAdd = false
    @State private var addedTitle: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch contentType {
                case .shows:   LibraryView(standalone: false, onAdd: { showingAdd = true })
                case .movies:  MoviesView(onAdd: { showingAdd = true })
                case .sports:  SportsView(onAdd: { showingAdd = true })
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
                    .padding(.bottom, 12)
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
        .modelContainer(for: [Show.self, Episode.self, Movie.self, SportTeam.self, SportGame.self], inMemory: true)
}
