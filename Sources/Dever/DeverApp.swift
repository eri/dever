import SwiftUI
import UserNotifications

@main
struct DeverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
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

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Show banners even while Dever is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// Clicking a notification brings Dever forward on that project.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo[Notifier.projectIDKey] as? String
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            if let raw, let id = UUID(uuidString: raw) {
                NotificationCenter.default.post(name: .openProject, object: id)
            }
            completionHandler()
        }
    }
}
