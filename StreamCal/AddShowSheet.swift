import SwiftUI
import SwiftData

struct AddShowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Pass an existing Show to edit it; nil = create new.
    var existingShow: Show? = nil

    @State private var title = ""
    @State private var platform = StreamingPlatform.netflix.rawValue
    @State private var notes = ""

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Show") {
                    TextField("Title", text: $title)
                    Picker("Platform", selection: $platform) {
                        ForEach(StreamingPlatform.allCases, id: \.rawValue) { p in
                            Text(p.rawValue).tag(p.rawValue)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(existingShow == nil ? "Add Show" : "Edit Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let show = existingShow {
                    title = show.title
                    platform = show.platform
                    notes = show.notes
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let show = existingShow {
            show.title = trimmedTitle
            show.platform = platform
            show.notes = notes
            show.updatedAt = .now
        } else {
            let newShow = Show(title: trimmedTitle, platform: platform, notes: notes)
            modelContext.insert(newShow)
        }
        dismiss()
    }
}

#Preview {
    AddShowSheet()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
