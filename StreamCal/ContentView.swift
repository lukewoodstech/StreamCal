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
            LibraryContainerView()
                .tabItem {
                    Label("Library", systemImage: "rectangle.stack.fill")
                }

            NextUpView()
                .tabItem {
                    Label("Next Up", systemImage: "play.circle.fill")
                }

            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
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

    var body: some View {
        NavigationStack {
            Group {
                switch contentType {
                case .shows:   LibraryView(standalone: false)
                case .movies:  MoviesView()
                case .sports:  SportsView()
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Content Type", selection: $contentType) {
                        ForEach(LibraryContentType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Show.self, Episode.self, Movie.self, SportTeam.self, SportGame.self], inMemory: true)
}
