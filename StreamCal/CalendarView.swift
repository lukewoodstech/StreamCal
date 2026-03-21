import SwiftUI
import SwiftData

struct CalendarView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Episode.airDate)
    private var allEpisodes: [Episode]

    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }

    // O(1) lookup: midnight-local date → episodes that day
    private var episodesByDate: [Date: [Episode]] {
        var dict: [Date: [Episode]] = [:]
        for day in WatchPlanner.calendarDays(from: allEpisodes) {
            dict[day.date] = day.episodes
        }
        return dict
    }

    private var selectedEpisodes: [Episode] {
        episodesByDate[selectedDate] ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MonthGridView(
                    displayedMonth: $displayedMonth,
                    selectedDate: $selectedDate,
                    episodesByDate: episodesByDate,
                    today: today,
                    onMonthChanged: { newMonth in
                        selectedDate = nearestDate(in: newMonth, from: episodesByDate) ?? cal.startOfMonth(for: newMonth)
                    },
                    onGoToToday: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            displayedMonth = cal.startOfMonth(for: today)
                            selectedDate = today
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Divider()

                dayPane
            }
            .navigationTitle("Calendar")
            .refreshable {
                await RefreshService.shared.refreshAllShows(modelContext: modelContext)
            }
            .onAppear {
                selectedDate = nearestDate(from: today, in: episodesByDate) ?? today
            }
            .onChange(of: episodesByDate.keys.count) {
                // Re-evaluate after a data refresh if still on today with no episodes
                if selectedEpisodes.isEmpty {
                    selectedDate = nearestDate(from: today, in: episodesByDate) ?? today
                }
            }
        }
    }

    /// Returns today if it has episodes, otherwise the next calendar day that does.
    private func nearestDate(from start: Date, in dict: [Date: [Episode]]) -> Date? {
        let sorted = dict.keys.filter { $0 >= start }.sorted()
        return sorted.first
    }

    /// Returns the first day in `month` that has episodes, or nil if none.
    private func nearestDate(in month: Date, from dict: [Date: [Episode]]) -> Date? {
        let monthStart = cal.startOfMonth(for: month)
        guard let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return nil }
        let sorted = dict.keys.filter { $0 >= monthStart && $0 < monthEnd }.sorted()
        return sorted.first
    }

    // MARK: - Day Pane

    private var dayPane: some View {
        Group {
            if selectedEpisodes.isEmpty {
                nothingScheduledView
            } else {
                List {
                    Section {
                        ForEach(selectedEpisodes) { episode in
                            CalendarEpisodeRow(episode: episode)
                        }
                    } header: {
                        dayPaneHeader
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var dayPaneHeader: some View {
        HStack {
            Text(headerLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(cal.isDateInToday(selectedDate) ? Color.accentColor : .primary)
            if !selectedEpisodes.isEmpty {
                Text("· \(selectedEpisodes.count) ep\(selectedEpisodes.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var headerLabel: String {
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        return selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var nothingScheduledView: some View {
        ContentUnavailableView(
            "Nothing Scheduled",
            systemImage: "calendar.badge.clock",
            description: Text("Add shows to your library to see upcoming episodes.")
        )
    }
}

// MARK: - Month Grid

struct MonthGridView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    let episodesByDate: [Date: [Episode]]
    let today: Date
    var onMonthChanged: ((Date) -> Void)? = nil
    var onGoToToday: (() -> Void)? = nil

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    private var canGoBack: Bool {
        displayedMonth > cal.startOfMonth(for: today)
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    // 42 cells (6 rows × 7 cols): nil = empty padding cell, Date = real day
    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: displayedMonth),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }

        // weekday index Mon=0 ... Sun=6
        let firstWeekday = (cal.component(.weekday, from: firstDay) + 5) % 7
        var result: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in range {
            result.append(cal.date(byAdding: .day, value: day - 1, to: firstDay))
        }
        // pad to complete grid
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            // Month navigation
            HStack {
                Button {
                    let newMonth = cal.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = newMonth }
                    onMonthChanged?(newMonth)
                } label: {
                    Image(systemName: "chevron.left")
                        .imageScale(.small)
                        .foregroundStyle(canGoBack ? .primary : .tertiary)
                }
                .disabled(!canGoBack)

                Spacer()
                Text(monthTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if !cal.isDate(selectedDate, inSameDayAs: today) || displayedMonth != cal.startOfMonth(for: today) {
                    Button("Today") { onGoToToday?() }
                        .font(.caption)
                        .fontWeight(.medium)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .transition(.opacity.combined(with: .scale))
                }
                Spacer()

                Button {
                    let newMonth = cal.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = newMonth }
                    onMonthChanged?(newMonth)
                } label: {
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                }
            }
            .padding(.vertical, 4)

            // Weekday header row
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }
            }

            // Day cells
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DayCell(
                            date: date,
                            isToday: cal.isDateInToday(date),
                            isSelected: cal.isDate(date, inSameDayAs: selectedDate),
                            isPast: date < today,
                            episodes: episodesByDate[date] ?? []
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedDate = date
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let isPast: Bool
    let episodes: [Episode]

    private var dayNumberColor: Color {
        if isSelected { return isToday ? .white : .primary }
        if isPast { return Color(.tertiaryLabel) }
        return .primary
    }

    /// Up to 3 dot colors: orange (today) or accent (future) per episode slot.
    private var dotColors: [Color] {
        guard !episodes.isEmpty else { return [] }
        let baseColor: Color = isToday ? .orange : .accentColor
        return Array(repeating: baseColor, count: min(3, episodes.count))
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(isToday ? Color.accentColor : Color(.systemGray4))
                        .frame(width: 30, height: 30)
                } else if isToday {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 30, height: 30)
                }

                Text(date.formatted(.dateTime.day()))
                    .font(.callout)
                    .fontWeight(isToday || isSelected ? .semibold : .regular)
                    .foregroundColor(dayNumberColor)
            }
            .frame(width: 30, height: 30)

            // Multi-dot episode indicator
            HStack(spacing: 2) {
                ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Calendar Episode Row

struct CalendarEpisodeRow: View {
    @Bindable var episode: Episode

    private var show: Show? { episode.show }

    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { cal.isDateInToday(episode.airDate) }

    private var posterURL: URL? {
        guard let s = show?.posterURL else { return nil }
        return URL(string: s)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Poster thumbnail — same height as before, orange border for today's drops
            CachedAsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 4)
                        .foregroundStyle(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                }
            }
            .frame(width: 30, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isToday ? Color.orange : Color.clear, lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(show?.title ?? "Unknown Show")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    if let show {
                        PlatformBadges(show: show)
                    }
                }
                Text(episode.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let show {
                EpisodeContextMenuItems(episode: episode, show: show)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                episode.isWatched.toggle()
                if let show {
                    Task { await NotificationService.shared.scheduleNotifications(for: show) }
                }
            } label: {
                Label(
                    episode.isWatched ? "Unwatch" : "Watched",
                    systemImage: episode.isWatched ? "eye.slash" : "checkmark"
                )
            }
            .tint(episode.isWatched ? .gray : .green)
        }
    }
}

// MARK: - Calendar helpers

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

// MARK: - Preview

#Preview {
    CalendarView()
        .modelContainer(calendarPreviewContainer)
}

private var calendarPreviewContainer: ModelContainer = {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Show.self, Episode.self, configurations: config)
    let ctx = container.mainContext

    let show1 = Show(title: "Severance", platform: "Apple TV+")
    ctx.insert(show1)
    let show2 = Show(title: "The Bear", platform: "Hulu")
    ctx.insert(show2)
    let show3 = Show(title: "The Last of Us", platform: "Max")
    ctx.insert(show3)

    for i in 0..<14 {
        let showIdx = i % 3
        let show = showIdx == 0 ? show1 : showIdx == 1 ? show2 : show3
        let ep = Episode(
            seasonNumber: 2,
            episodeNumber: i + 1,
            title: "Episode \(i + 1)",
            airDate: Calendar.current.date(byAdding: .day, value: i * 3, to: .now)!
        )
        ep.show = show
        ctx.insert(ep)
    }
    return container
}()
