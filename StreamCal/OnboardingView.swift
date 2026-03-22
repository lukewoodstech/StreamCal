import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            systemImage: "rectangle.stack.fill",
            imageColor: .blue,
            title: "Your Streaming Library",
            description: "Add TV shows, movies, and sports teams in one place. StreamCal keeps everything organized so you never lose track."
        ),
        OnboardingPage(
            systemImage: "play.circle.fill",
            imageColor: .indigo,
            title: "What's Next Up",
            description: "See exactly what's airing this week — episodes, theatrical releases, and upcoming games, all in one feed."
        ),
        OnboardingPage(
            systemImage: "calendar",
            imageColor: .purple,
            title: "A Calendar Built for Streaming",
            description: "Browse any date to see what's dropping. Episodes, movies, and game days shown together at a glance."
        ),
        OnboardingPage(
            systemImage: "bell.badge.fill",
            imageColor: .orange,
            title: "Never Miss a Drop",
            description: "Get reminded when new episodes air and when games tip off. Customize your reminder times in Settings."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Page indicators + button
            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.primary : Color(.systemGray4))
                            .frame(width: index == currentPage ? 20 : 8, height: 8)
                            .animation(.spring(duration: 0.3), value: currentPage)
                    }
                }

                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                .padding(.horizontal, 32)

                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        hasCompletedOnboarding = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Color.clear.frame(height: 20)
                }
            }
            .padding(.bottom, 48)
            .padding(.top, 16)
        }
        .background(Color(.systemBackground))
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.imageColor.opacity(0.12))
                    .frame(width: 140, height: 140)
                Image(systemName: page.systemImage)
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(page.imageColor)
            }

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }
}

private struct OnboardingPage {
    let systemImage: String
    let imageColor: Color
    let title: String
    let description: String
}

#Preview {
    OnboardingView()
}
