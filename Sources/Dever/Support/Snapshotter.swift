import AppKit
import SwiftUI

/// Development aid: launched with `DEVER_SNAPSHOT_DIR=<folder>`, Dever walks through its
/// main screens in light and dark mode, saves a PNG of its own window for each, then quits.
/// It draws the window's own views, so no screen-recording permission is needed.
@MainActor
enum Snapshotter {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(in dir: URL, projects: [Project]) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var screens: [(String, SidebarItem)] = [("overview", .overview)]
        if let first = projects.first { screens.append(("project", .project(first.id))) }
        screens.append(("accounts", .accounts))

        // Let the first refresh land before the first picture; DEVER_SNAPSHOT_WAIT=0 captures
        // the loading state instead.
        let wait = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_WAIT"].flatMap(Double.init) ?? 15
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        for (themeName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for (name, item) in screens {
                NotificationCenter.default.post(name: .showScreen, object: item)
                let settle: Double = wait == 0 ? 0.4 : (item == .overview ? 3 : 8)
                try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
                capture(to: dir.appendingPathComponent("\(name)-\(themeName).png"))
            }
        }
        NSApp.terminate(nil)
    }

    private static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

extension Notification.Name {
    /// Switches the main window to a screen; `object` is a `SidebarItem`.
    static let showScreen = Notification.Name("dever.showScreen")
}
