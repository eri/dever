import SwiftUI

@main
struct DeverApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("Dever") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
