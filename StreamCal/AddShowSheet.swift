import SwiftUI
import SwiftData

struct AddShowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var title = ""
    @State private var platform = ""
    
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !platform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Show") {
                    TextField("Title", text: $title)
                    TextField("Platform (Netflix, Hulu, etc.)", text: $platform)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Add Show")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private func save() {
        let newShow = Show(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            platform: platform.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(newShow)
        dismiss()
    }
}
