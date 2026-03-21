import SwiftUI

// MARK: - Design Tokens

enum DS {

    // MARK: Colors

    enum Color {
        /// `Color(red: 0.95, green: 0.35, blue: 0.35)` — "In Theaters" status, calendar border
        static let movieTheaterRed = SwiftUI.Color(red: 0.95, green: 0.35, blue: 0.35)
        /// `Color(.systemGray5)` — image placeholder backgrounds
        static let imagePlaceholder = SwiftUI.Color(.systemGray5)
    }

    // MARK: Corner Radius

    enum Radius {
        static let xs: CGFloat    = 4   // tiny indicators, game badges in rows
        static let sm: CGFloat    = 6   // list row thumbnails, team logos
        static let md: CGFloat    = 8   // NextUp cards, episode posters
        static let lg: CGFloat    = 12  // detail view posters
        static let toast: CGFloat = 14  // toast, bottom sheet modals
        static let modal: CGFloat = 20  // settings modals (continuous style)
    }

    // MARK: Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat  = 4
        static let sm: CGFloat  = 8
        static let md: CGFloat  = 12
        static let lg: CGFloat  = 16
        static let xl: CGFloat  = 24
    }

    // MARK: Image Sizes

    enum ImageSize {
        static let listRow      = CGSize(width: 44, height: 66)   // library rows (Show, Movie)
        static let card         = CGSize(width: 54, height: 81)   // NextUp cards
        static let searchResult = CGSize(width: 46, height: 69)   // add-sheet search results
        static let calendarRow  = CGSize(width: 30, height: 44)   // calendar day pane rows
        static let teamSm       = CGSize(width: 32, height: 32)   // GameRowView badge
        static let teamMd       = CGSize(width: 40, height: 40)   // UpcomingGameRow badge
        static let teamLg       = CGSize(width: 64, height: 64)   // TeamDetailView header
        static let detailPoster = CGSize(width: 160, height: 240) // ShowDetailView / MovieDetailView
    }
}

// MARK: - View Extensions

extension View {

    /// Colored pill badge — the standard pattern for status chips, platform badges, countdown pills.
    ///
    /// Example:
    /// ```swift
    /// Text("In Theaters").statusBadge(color: DS.Color.movieTheaterRed)
    /// ```
    func statusBadge(color: Color) -> some View {
        self
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    /// Light shadow — toasts and floating cards.
    func lightShadow() -> some View {
        shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    /// Medium shadow — detail view posters and prominent cards.
    func mediumShadow() -> some View {
        shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    /// Heavy shadow — settings modals and full-screen overlays.
    func heavyShadow() -> some View {
        shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
    }
}
