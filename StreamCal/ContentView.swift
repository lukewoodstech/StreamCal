import SwiftUI

struct ContentView: View {
    
    var body: some View {
        TabView {
            
            NextUpView()
                .tabItem {
                    Image(systemName: "play.circle.fill")
                    Text("Next Up")
                }
            
            CalendarView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Calendar")
                }
            
            LibraryView()
                .tabItem {
                    Image(systemName: "rectangle.stack.fill")
                    Text("Library")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
        }
    }
}

#Preview {
    ContentView()
}
