import SwiftUI

struct CalendarView: View {
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                
                Image(systemName: "calendar")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("Calendar")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your upcoming episodes by date will appear here.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
            }
            .padding()
            .navigationTitle("Calendar")
        }
    }
}

#Preview {
    CalendarView()
}
