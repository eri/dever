import SwiftUI

@main
struct DeverApp: App {
    @StateObject private var app = AppState()
    @StateObject private var store = OverviewStore()

    var body: some Scene {
        WindowGroup("Dever") {
            ContentView()
                .environmentObject(app)
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
