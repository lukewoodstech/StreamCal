import SwiftUI

struct NextUpView: View {
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                
                Text("Next Up")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your upcoming episodes will appear here.")
                    .foregroundColor(.secondary)
                
            }
            .navigationTitle("Next Up")
        }
    }
}

#Preview {
    NextUpView()
}
