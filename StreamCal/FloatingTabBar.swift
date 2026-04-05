import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: Int

    private let items: [(icon: String, label: String)] = [
        ("calendar", "Calendar"),
        ("rectangle.stack.fill", "Library"),
        ("play.circle.fill", "Next Up"),
        ("gearshape.fill", "Settings")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                tabButton(index: index)
            }
        }
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func tabButton(index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button {
            guard selectedTab != index else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: items[index].icon)
                    .font(.system(size: 19))
                    .symbolRenderingMode(.hierarchical)
                Text(items[index].label)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
