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
        // DEVER_SNAPSHOT_PROJECT=<index> picks another project than the first.
        let index = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_PROJECT"].flatMap(Int.init) ?? 0
        // The Overview demo replaces the projects: their pages do not exist, only the Overview is captured.
        if projects.indices.contains(index), ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_OVERVIEW_DEMO"] == nil {
            screens.append(("project", .project(projects[index].id)))
        }
        screens.append(("settings", .settings))

        // Let the first refresh land before the first picture; DEVER_SNAPSHOT_WAIT=0 captures
        // the loading state instead.
        let wait = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_WAIT"].flatMap(Double.init) ?? 15
        // DEVER_SNAPSHOT_SIZE=1080x680 captures at that window size (the minimum, say).
        if let raw = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SIZE"] {
            let parts = raw.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.setContentSize(NSSize(width: parts[0], height: parts[1]))
            }
        }
        // DEVER_SNAPSHOT_ZOOM=1 zooms the window; DEVER_SNAPSHOT_ZOOM=click sends it a
        // double-click on its title bar instead. Both write the resulting frame next to the
        // screen's, to check that zoom can fill it.
        if let zoom = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_ZOOM"], zoom == "1" || zoom == "click",
           let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            if zoom == "click" {
                let point = NSPoint(x: window.frame.width / 2, y: window.frame.height - 20)
                for (type, count) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 1), (.leftMouseDown, 2), (.leftMouseUp, 2)] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1) {
                        NSApp.sendEvent(event)
                    }
                }
            } else {
                window.zoom(nil)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            let screen = window.screen?.visibleFrame ?? .zero
            try? "window \(window.frame)\nscreen \(screen)\n".write(to: dir.appendingPathComponent("zoom.txt"), atomically: true, encoding: .utf8)
        }
        // In front and unoccluded: SwiftUI pauses animations in a covered window, which would
        // freeze every transition mid-way in the pictures.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
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
                // An open popover (the overview's View options, say) is written beside it.
                capturePopover(to: dir.appendingPathComponent("\(name)-\(themeName)-popover.png"))
                // DEVER_SNAPSHOT_SCROLL_END=1 adds each screen scrolled to its end.
                if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SCROLL_END"] == "1" {
                    scrollToEnd()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    capture(to: dir.appendingPathComponent("\(name)-\(themeName)-end.png"))
                }
            }
        }
        if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SLACK_WIDE"] == "1", let first = projects.first {
            // The first project's conversation at full width, in both modes.
            for (themeName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                NotificationCenter.default.post(name: .showScreen, object: SidebarItem.project(first.id))
                try? await Task.sleep(nanoseconds: UInt64((wait == 0 ? 0.4 : 8) * 1_000_000_000))
                NotificationCenter.default.post(name: .toggleSlackWide, object: nil)
                // DEVER_SNAPSHOT_SLACK_MID=1 also captures the room while it is still growing
                // (about a third of the way through its spring) and while the thread slides in.
                let mid = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SLACK_MID"] == "1"
                if mid { await filmstrip(dir, "project-slack-mid-\(themeName)") }
                try? await Task.sleep(nanoseconds: UInt64((wait == 0 ? 0.4 : 6) * 1_000_000_000))
                capture(to: dir.appendingPathComponent("project-slack-wide-\(themeName).png"))
                if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SLACK_THREAD"] == "1" {
                    NotificationCenter.default.post(name: .openFirstSlackThread, object: nil)
                    if mid { await filmstrip(dir, "project-slack-thread-mid-\(themeName)") }
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    capture(to: dir.appendingPathComponent("project-slack-thread-\(themeName).png"))
                    NotificationCenter.default.post(name: .openFirstSlackThread, object: nil)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SLACK_PREVIEW"] == "1" {
                    NotificationCenter.default.post(name: .previewFirstSlackFile, object: nil)
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    capture(to: dir.appendingPathComponent("slack-preview-\(themeName).png"))
                    NotificationCenter.default.post(name: .previewSlackFile, object: nil)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
                NotificationCenter.default.post(name: .toggleSlackWide, object: nil)
                if mid { await filmstrip(dir, "project-slack-back-mid-\(themeName)") }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
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
        if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SETTINGS"] == "1" {
            // Every Settings section, in both modes.
            for (themeName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                NotificationCenter.default.post(name: .showScreen, object: SidebarItem.settings)
                for section in SettingsView.Section.visible {
                    NotificationCenter.default.post(name: .showSettingsSection, object: section.rawValue)
                    try? await Task.sleep(nanoseconds: UInt64((wait == 0 ? 0.4 : 2.5) * 1_000_000_000))
                    capture(to: dir.appendingPathComponent("settings-\(section.rawValue)-\(themeName).png"))
                }
            }
        }
        if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_ONBOARDING"] == "1" {
            NotificationCenter.default.post(name: .showOnboarding, object: nil)
            for (themeName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                // DEVER_SNAPSHOT_STAGE_WAIT=<seconds> holds each stage longer (default 1.5).
                let hold = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_STAGE_WAIT"].flatMap(Double.init) ?? 1.5
                for stage in OnboardingView.Stage.allCases {
                    NotificationCenter.default.post(name: .showOnboardingStage, object: stage.rawValue)
                    try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
                    capture(to: dir.appendingPathComponent("onboarding-\(stage)-\(themeName).png"))
                }
            }
        }
        // Every button role in every state (hover and press forced through the style's override),
        // in its own window, in both modes: buttons-dark.png, buttons-light.png. With
        // DEVER_SNAPSHOT_INTELLIGENCE set, generated text in its states too: generated-*.png.
        var galleries: [(name: String, view: AnyView)] = []
        if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_GALLERY"] == "1" {
            galleries.append(("buttons", AnyView(ButtonGallery())))
            if IntelligenceStatus.snapshotOverride != nil { galleries.append(("generated", AnyView(GeneratedGallery()))) }
        }
        for gallery in galleries {
            for (themeName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                let host = NSHostingView(rootView: gallery.view)
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.orderFront(nil)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(gallery.name)-\(themeName).png"))
                }
                window.orderOut(nil)
            }
        }
        NSApp.terminate(nil)
    }

    /// Eight frames, one every 60 ms, of a transition that has just been started: a filmstrip.
    private static func filmstrip(_ dir: URL, _ name: String) async {
        for i in 0..<8 {
            try? await Task.sleep(nanoseconds: 60_000_000)
            capture(to: dir.appendingPathComponent("\(name)-\(i).png"))
        }
    }

    /// Scrolls the main window's outermost scroll view to its end.
    private static func scrollToEnd() {
        guard let main = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }), let root = main.contentView else { return }
        func all(_ v: NSView) -> [NSScrollView] {
            (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(all)
        }
        // The tallest document is the screen's own scroll view, not a list inside a panel.
        guard let scroll = all(root).max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }),
              let doc = scroll.documentView else { return }
        let y = max(0, doc.bounds.height - scroll.contentView.bounds.height)
        doc.scroll(NSPoint(x: 0, y: doc.isFlipped ? y : 0))
        scroll.reflectScrolledClipView(scroll.contentView)
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
    /// Toggles the project page's wide Slack view (snapshots).
    static let toggleSlackWide = Notification.Name("dever.toggleSlackWide")
}
