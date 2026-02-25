import SwiftUI
import SwiftData

struct LibraryView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \Show.createdAt, order: .reverse)
    private var shows: [Show]
    
    @State private var showingAddShow = false
    
    
    var body: some View {
        
        NavigationStack {
            
            Group {
                
                if shows.isEmpty {
                    
                    ContentUnavailableView(
                        "No shows yet",
                        systemImage: "rectangle.stack.fill",
                        description: Text("Tap + to add your first show.")
                    )
                    
                } else {
                    
                    List {
                        
                        ForEach(shows) { show in
                            
                            VStack(alignment: .leading, spacing: 4) {
                                
                                Text(show.title)
                                    .font(.headline)
                                
                                Text(show.platform)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                            }
                            
                        }
                        .onDelete(perform: deleteShows)
                        
                    }
                    
                }
                
            }
            
            .navigationTitle("Library")
            
            .toolbar {
                
                ToolbarItem(placement: .topBarTrailing) {
                    
                    Button {
                        showingAddShow = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    
                }
                
            }
            
            .sheet(isPresented: $showingAddShow) {
                AddShowSheet()
            }
            
        }
        
    }
    
    
    private func deleteShows(at offsets: IndexSet) {
        
        for index in offsets {
            modelContext.delete(shows[index])
        }
        
    }
    
}


#Preview {
    LibraryView()
}
