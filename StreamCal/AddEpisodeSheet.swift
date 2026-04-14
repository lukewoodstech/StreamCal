import SwiftUI
import SwiftData

struct AddEpisodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let show: Show

    @State private var seasonNumber = 1
    @State private var episodeNumber = 1
    @State private var title = ""
    @State private var airDate = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section("Episode") {
                    Stepper("Season \(seasonNumber)", value: $seasonNumber, in: 1...99)
                    Stepper("Episode \(episodeNumber)", value: $episodeNumber, in: 1...999)
                    TextField("Title (optional)", text: $title)
                }

                Section("Air Date") {
                    DatePicker("Air Date", selection: $airDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

            }
            .navigationTitle("Add Episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                let existing = show.sortedEpisodes
                if let last = existing.last {
                    seasonNumber = last.seasonNumber
                    episodeNumber = last.episodeNumber + 1
                }
            }
        }
    }

    private func save() {
        let episode = Episode(
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            airDate: airDate
        )
        episode.show = show
        modelContext.insert(episode)
        show.updatedAt = .now
        dismiss()
    }
}

#Preview {
    AddEpisodeSheetPreviewWrapper()
}

private struct AddEpisodeSheetPreviewWrapper: View {
    var body: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Show.self, Episode.self, configurations: config)
        let show = Show(title: "Severance", platform: "Apple TV+")
        container.mainContext.insert(show)
        return AddEpisodeSheet(show: show)
            .modelContainer(container)
    }
}

