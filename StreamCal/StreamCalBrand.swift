import SwiftUI

// MARK: - Brand Mark

/// The StreamCal logo mark: calendar base with a play button overlay.
/// Matches the app icon motif. Use `size` to scale uniformly.
struct BrandMark: View {
    var size: CGFloat = 32
    var showBackground: Bool = false

    var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.43, green: 0.36, blue: 0.90),
                                     Color(red: 0.30, green: 0.20, blue: 0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 1.25, height: size * 1.25)
            }

            Image(systemName: "calendar")
                .font(.system(size: size, weight: .light))
                .foregroundStyle(showBackground ? .white.opacity(0.9) : Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(showBackground ? .white : Color.accentColor)
                .offset(y: size * 0.08)
        }
    }
}

// MARK: - Wordmark

/// Horizontal logo mark + "StreamCal" text. Use in nav bars and headers.
struct Wordmark: View {
    var iconSize: CGFloat = 18
    var font: Font = .headline

    var body: some View {
        HStack(spacing: 6) {
            BrandMark(size: iconSize)
            Text("StreamCal")
                .font(font)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        BrandMark(size: 80, showBackground: true)
        BrandMark(size: 48)
        Wordmark()
        Wordmark(iconSize: 22, font: .title3)
    }
    .padding(40)
}
