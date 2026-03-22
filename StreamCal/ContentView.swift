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
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text("Library")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Show.self, Episode.self, Movie.self, SportTeam.self, SportGame.self], inMemory: true)
}
