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
        screens.append(("settings", .settings))

        // Let the first refresh land before the first picture; DEVER_SNAPSHOT_WAIT=0 captures
        // the loading state instead.
        let wait = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_WAIT"].flatMap(Double.init) ?? 15
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        // DEVER_SNAPSHOT_SCREENS=0 skips the main screens when only sheets or onboarding are wanted.
        let wantScreens = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SCREENS"] != "0"
        for (themeName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] where wantScreens {
            NSApp.appearance = NSAppearance(named: appearance)
            for (name, item) in screens {
                NotificationCenter.default.post(name: .showScreen, object: item)
                let settle: Double = wait == 0 ? 0.4 : (item == .overview ? 3 : 8)
                try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
                capture(to: dir.appendingPathComponent("\(name)-\(themeName).png"))
            }
        }
        if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_ISSUE"] == "1", let first = projects.first {
            // The first project's first listed issue, in both modes.
            for (themeName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                NotificationCenter.default.post(name: .showScreen, object: SidebarItem.project(first.id))
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                NotificationCenter.default.post(name: .openFirstIssue, object: nil)
                try? await Task.sleep(nanoseconds: UInt64((wait == 0 ? 0.4 : 8) * 1_000_000_000))
                capture(to: dir.appendingPathComponent("issue-\(themeName).png"))
                capturePopover(to: dir.appendingPathComponent("issue-\(themeName)-popover.png"))
                NotificationCenter.default.post(name: .scrollToEnd, object: nil)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                capture(to: dir.appendingPathComponent("issue-\(themeName)-end.png"))
            }
        }
        if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SHEETS"] == "1" {
            // Sheets are captured dark unless DEVER_SNAPSHOT_SHEET_THEME=light.
            let light = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SHEET_THEME"] == "light"
            NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
            NotificationCenter.default.post(name: .showScreen, object: SidebarItem.overview)
            for (name, sheet) in [("sheet-import-slack", "import-slack"), ("sheet-import-linear", "import-linear"),
                                  ("sheet-new-project", "new-project"), ("sheet-github", "github")] {
                NotificationCenter.default.post(name: .showSheet, object: sheet)
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                capture(to: dir.appendingPathComponent("\(name).png"))
                capturePopover(to: dir.appendingPathComponent("\(name)-popover.png"))
                NotificationCenter.default.post(name: .showSheet, object: "none")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_ONBOARDING"] == "1" {
            NotificationCenter.default.post(name: .showOnboarding, object: nil)
            for (themeName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                for stage in OnboardingView.Stage.allCases {
                    NotificationCenter.default.post(name: .showOnboardingStage, object: stage.rawValue)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    capture(to: dir.appendingPathComponent("onboarding-\(stage)-\(themeName).png"))
                }
            }
        }
        NSApp.terminate(nil)
    }

    /// An open popover lives in its own window; nothing is written when none is open.
    private static func capturePopover(to url: URL) {
        guard let popover = NSApp.windows.first(where: { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }),
              let view = popover.contentView?.superview ?? popover.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func capture(to url: URL) {
        guard let main = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              case let window = main.attachedSheet ?? main,
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

extension Notification.Name {
    /// Switches the main window to a screen; `object` is a `SidebarItem`.
    static let showScreen = Notification.Name("dever.showScreen")
    /// Opens or closes a sheet by name (snapshots): import-slack, import-linear, new-project, github, none.
    static let showSheet = Notification.Name("dever.showSheet")
    /// Opens the onboarding flow (Help menu, snapshots).
    static let showOnboarding = Notification.Name("dever.showOnboarding")
}
