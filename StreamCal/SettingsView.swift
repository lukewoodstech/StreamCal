import SwiftUI

struct SettingsView: View {
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("App preferences and notifications.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
            }
            .padding()
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
