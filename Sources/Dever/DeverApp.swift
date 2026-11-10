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
                // No upper bound: zooming (double-click on the title bar or on an edge) may take
                // the whole screen. Without it, SwiftUI caps the window at the content's ideal size.
                .frame(minWidth: 1080, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .help) {
                Button("Welcome to Dever…") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var titleBarClicks: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // The content view runs under the transparent title bar, so a double-click there
        // reaches SwiftUI instead of the frame and the window never zooms. Do what the
        // frame would have done: the action set in System Settings for a title bar
        // double-click (zoom by default).
        titleBarClicks = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.clickCount == 2, let window = event.window, window.canBecomeMain,
                  window.styleMask.contains(.fullSizeContentView),
                  event.locationInWindow.y > window.contentLayoutRect.maxY else { return event }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "None": return event
            case "Minimize": window.performMiniaturize(nil)
            default: window.performZoom(nil)
            }
            return nil
        }
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
