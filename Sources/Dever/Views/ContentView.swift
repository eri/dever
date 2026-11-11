import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case settings
    case project(UUID)
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    @State private var selection: SidebarItem = .overview
    /// Pages pushed over the selected screen (an issue, then the issues it links to).
    @State private var path = NavigationPath()
    @State private var showNew = false
    @State private var importSource: ImportSheet.Source?
    @State private var editing: Project?
    @State private var removing: Project?
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage("displayName") private var displayName = ""
    @AppStorage(GenerativeAvatar.seedKey) private var avatarSeedRaw = ""
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
    @State private var showOnboarding = false
    @State private var githubSheet = false
    /// The project whose rail menu is open (a right click, a control click, ⌥↩ on its tile).
    @State private var menuProject: Project?
    /// Snapshots: the tile whose tooltip is shown without a pointer.
    @State private var forcedTip: UUID?
    /// The open menu's height, to keep it inside the window when its tile sits low.
    @State private var menuHeight: CGFloat = 0

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(finish: endOnboarding)
            } else {
                main
            }
        }
        .onChange(of: appearance, initial: true) { _, value in
            Appearance(rawValue: value)?.apply()
        }
        .onAppear {
            // New users only: anyone who already has projects has been through setup.
            if !app.projects.isEmpty { onboardingDone = true }
            showOnboarding = !onboardingDone || ProcessInfo.processInfo.environment["DEVER_ONBOARDING"] == "1"
            // Settings › Open at launch: back on the project left open, when it still exists.
            if Preferences.landing == .lastProject, let id = Preferences.lastProjectID,
               app.projects.contains(where: { $0.id == id }) {
                selection = .project(id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in showOnboarding = true }
    }

    private func endOnboarding(_ exit: OnboardingExit) {
        onboardingDone = true
        showOnboarding = false
        selection = .overview
        switch exit {
        case .overview: break
        case .newProject: showNew = true
        case .importSlack: importSource = .slack
        case .importLinear: importSource = .linear
        }
    }

    private var main: some View {
        HStack(spacing: 0) {
            rail
            Rectangle().fill(Theme.border).frame(width: 1)
            NavigationStack(path: $path) {
            // Screens dissolve into each other (150 ms): core navigation gets no movement.
            Group {
                switch selection {
                case .project(let id):
                    if let p = app.projects.first(where: { $0.id == id }) {
                        ProjectDetailView(project: p, edit: { editing = p }).id(p.id)
                    } else {
                        ContentUnavailableView("Project not found", systemImage: "questionmark.folder",
                                               description: Text("It may have been removed. Pick another project in the sidebar."))
                            .sheetBackground()
                    }
                case .settings:
                    SettingsView()
                case .overview:
                    OverviewView(open: { selection = .project($0.id) },
                                 newProject: { showNew = true },
                                 importFrom: { importSource = $0 },
                                 link: { project, step in
                                     ProjectEditorSheet.openAt = step
                                     editing = project
                                 })
                }
            }
            .id(selection)
            .transition(.opacity)
            .motion(.easeOut(duration: 0.15), fade: true, value: selection)
            .environment(\.openSettings, { selection = .settings })
            .background(Theme.frame)
            .toolbarBackgroundHiddenIfAvailable()
            .navigationDestination(for: IssueRoute.self) { IssueDetailView(route: $0) }
            }
        }
        .onChange(of: selection) { _, value in
            path = NavigationPath()
            menuProject = nil
            if case .project(let id) = value { Preferences.lastProjectID = id }
        }
        // The rail's tooltips and the tile menu are drawn here, over the whole window, so the
        // rail's own clip (its scroll view) never cuts them.
        .tipHost()
        .overlayPreferenceValue(RailMenuKey.self) { railMenuOverlay($0) }
        .closesOnOutsideClick(menuProject != nil) { Motion.run(Motion.ui, fade: true) { menuProject = nil } }
        .onReceive(NotificationCenter.default.publisher(for: .showRailMenu)) { note in
            // Snapshots: opens the first project's menu (or closes it with "none").
            menuProject = (note.object as? String) == "none" ? nil : app.projects.first
        }
        .onReceive(NotificationCenter.default.publisher(for: .showRailTip)) { note in
            forcedTip = (note.object as? String) == "none" ? nil : app.projects.first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .openIssue)) { note in
            if let route = note.object as? IssueRoute { path.append(route) }
        }
        // Links to the tools leave through here: what they show may change while you are away.
        .environment(\.openURL, OpenURLAction { url in
            LookAgain.shared.openedExternally(url)
            return .systemAction
        })
        // Back in front, awake or online again: the Overview refreshes at once when it is the
        // screen in front, otherwise when its cycle is due (a project page looks after itself).
        .onReceive(NotificationCenter.default.publisher(for: .lookAgain)) { _ in
            guard Snapshotter.directory == nil else { return }
            let due = selection == .overview && path.isEmpty ? LookAgain.shared.isDue(store.lastRefresh) : store.isStale
            if due { Task { await store.refresh(app, quiet: true) } }
        }
        // The Overview in front reads its rows again every minute; behind, at the setting.
        .onChange(of: selection == .overview && path.isEmpty, initial: true) { _, front in store.inFront = front }
        .task {
            LookAgain.shared.start()
            store.startAutoRefresh(app)
            // Ask once, when there is something to be notified about.
            if !app.projects.isEmpty, await Notifier.shared.authorizationStatus() == .notDetermined {
                _ = await Notifier.shared.requestAuthorization()
            }
        }
        .task {
            if let dir = Snapshotter.directory { await Snapshotter.run(in: dir, projects: app.projects, app: app) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSheet)) { note in
            importSource = nil; showNew = false; githubSheet = false; editing = nil
            switch note.object as? String {
            case "import-slack": importSource = .slack
            case "import-linear": importSource = .linear
            case "new-project": showNew = true
            case "edit-project": editing = app.projects.first
            case "github": githubSheet = true
            default: break
            }
        }
        .sheet(isPresented: $githubSheet) { GitHubLoginSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .showScreen)) { note in
            if let item = note.object as? SidebarItem { selection = item; path = NavigationPath() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProject)) { note in
            if let id = note.object as? UUID, app.projects.contains(where: { $0.id == id }) {
                selection = .project(id)
            }
        }
        .sheet(isPresented: $showNew) { ProjectEditorSheet() }
        .sheet(item: $importSource) { ImportSheet(source: $0) }
        .sheet(item: $editing) { ProjectEditorSheet(project: $0, isNew: false) }
        .confirmationDialog(
            "Remove \u{201C}\(removing?.name ?? "")\u{201D} from Dever?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { project in
            Button("Remove project", role: .destructive) {
                if selection == .project(project.id) { selection = .overview }
                app.delete(project)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Dever stops tracking it. The Slack channel and the Linear project are not changed.")
        }
    }

    /// The open tile's menu, hung beside the tile and kept inside the window.
    @ViewBuilder
    private func railMenuOverlay(_ anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { geo in
            if let anchor, let project = menuProject {
                let bounds = geo[anchor]
                RailMenu(project: project, isCurrent: selection == .project(project.id),
                         unread: store.snapshots[project.id]?.slack?.unread,
                         open: { selection = .project(project.id); menuProject = nil },
                         edit: { menuProject = nil; editing = project },
                         remove: { menuProject = nil; removing = project },
                         close: { menuProject = nil })
                         .background(GeometryReader { m in Color.clear.onAppear { menuHeight = m.size.height } })
                         .offset(x: bounds.maxX + 8, y: min(bounds.minY, max(12, geo.size.height - menuHeight - 12)))
                         .transition(Motion.pop)
            }
        }
        .motion(Motion.ui, value: menuProject?.id)
    }

    // MARK: Rail

    /// A slim rail instead of a sidebar: the projects are a handful of tiles, so they don't
    /// need 240px. Every icon has a tooltip and an accessible name.
    private var rail: some View {
        VStack(spacing: 6) {
            DeverMark().frame(width: 22, height: 22)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .sootTip("Dever", detail: scope)
                .accessibilityLabel("Dever, \(scope)")
            railButton(symbol: "square.grid.2x2", label: "Overview", item: .overview)
            Rectangle().fill(Theme.border).frame(width: 28, height: 1).padding(.vertical, 8)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(app.projects) { p in projectTile(p) }
                    addMenu.frame(width: 40, height: 40)
                }
            }
            Spacer(minLength: 0)
            userTile.padding(.bottom, 14)
        }
        .frame(width: 64)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.frame)
    }

    /// Your generated picture: the stored seed, drawn once when there is none.
    private var avatarSeed: UInt64 { UInt64(avatarSeedRaw) ?? GenerativeAvatar.storedSeed }

    private var scope: String {
        app.linear?.account.orgName ?? app.slack?.teamName ?? "No workspace connected"
    }

    private func railButton(symbol: String, label: String, item: SidebarItem) -> some View {
        let on = selection == item
        return Button { selection = item } label: {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(on ? Theme.text : Theme.muted)
                .frame(width: 40, height: 40)
                .background(on ? Theme.active : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .motion(Motion.quick, fade: true, value: on)
        }
        .buttonStyle(IconButton(fill: nil, radius: 10))
        .sootTip(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A project as its initials on its own tint, with a dot when it needs attention.
    private func projectTile(_ p: Project) -> some View {
        let status = p.status(store.snapshots[p.id])
        let on = selection == .project(p.id)
        let detail = tileDetail(p, status)
        return tileButton(p, status: status, on: on)
            .sootTip(p.name, detail: detail, forced: forcedTip == p.id)
            // The menu: a right click or a control click on the tile, ⌥↩ while it has the focus;
            // VoiceOver gets the same actions on the tile itself.
            .onRightClick { Motion.run(Motion.ui) { menuProject = p } }
            .onKeyPress(phases: .down) { press in
                guard press.key == .return, press.modifiers.contains(.option) else { return .ignored }
                Motion.run(Motion.ui) { menuProject = p }
                return .handled
            }
            .anchorPreference(key: RailMenuKey.self, value: .bounds) { menuProject?.id == p.id ? $0 : nil }
            .accessibilityLabel("\(p.name), \(detail)")
            .accessibilityHint("Opens the project. Option Return for its menu")
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityAction(named: "Edit project") { editing = p }
            .accessibilityAction(named: p.favorite == true ? "Unpin from top" : "Pin to top") { app.setFavorite(p, p.favorite != true) }
            .accessibilityAction(named: "Remove from Dever") { removing = p }
    }

    private func tileButton(_ p: Project, status: ProjectStatus, on: Bool) -> some View {
        let initials = p.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return Button { selection = .project(p.id) } label: {
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.75))
                .frame(width: 36, height: 36)
                .background(PersonTint.color(for: p.name), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if status == .needsAttention || status == .quiet {
                        Circle().fill(status.tint).frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Theme.frame, lineWidth: 2))
                            .offset(x: 3, y: -3)
                    }
                }
                .padding(2)
                // The ring fades in (120 ms); the tile itself answers the press with a small scale.
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Theme.text : .clear, lineWidth: 2))
                .motion(Motion.quick, fade: true, value: on)
        }
        .buttonStyle(IconButton(fill: nil, radius: 12))
        .keepsMenuOpen()
        }

    /// You, opening Settings; a dot while an account still needs connecting.
    private var userTile: some View {
        let on = selection == .settings
        let name = displayName.isEmpty ? "Settings" : displayName
        return Button { selection = .settings } label: {
            GenerativeAvatar(seed: avatarSeed, size: 32)
                .overlay(alignment: .topTrailing) {
                    // Amber: something to connect. Negative: a token the service rejected.
                    if missingAccounts > 0 || !app.expired.isEmpty {
                        Circle().fill(app.expired.isEmpty ? Theme.chart3 : Theme.negative).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Theme.frame, lineWidth: 2))
                            .offset(x: 2, y: -2)
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(on ? Theme.text : .clear, lineWidth: 2))
                .motion(Motion.quick, fade: true, value: on)
        }
        .buttonStyle(IconButton(fill: nil))
        .sootTip(name, detail: accountsHint ?? "Settings")
        .accessibilityLabel(accountsHint.map { "Settings, \($0)" } ?? "Settings")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var addMenu: some View {
        Button { showNew = true } label: {
            Image(systemName: "plus").foregroundStyle(Theme.muted).frame(width: 40, height: 40)
        }
        .buttonStyle(IconButton(fill: nil, radius: 10))
        .keyboardShortcut("n")
        .sootTip("Add a project", detail: "⌘N")
        .accessibilityLabel("Add project")
    }

    /// The second line of a tile's tooltip: its health, then what waits in Slack when the store knows.
    private func tileDetail(_ p: Project, _ status: ProjectStatus) -> String {
        var parts = [status.label]
        if let snapshot = store.snapshots[p.id] {
            if let slack = snapshot.slack, let unread = slack.unread, unread > 0 {
                parts.append("\(slack.unreadCapped ? "200+" : "\(unread)") unread")
            }
            // The same things the Overview lists under the project.
            let waiting = snapshot.waiting(channel: p.slack?.name, channelID: p.slack?.id).count
            if waiting > 0 { parts.append("\(waiting) for you") }
        }
        return parts.joined(separator: " · ")
    }

    private var missingAccounts: Int {
        [app.slack == nil, app.linear == nil].filter { $0 }.count
    }

    /// What the dot on the user tile means, in words.
    private var accountsHint: String? {
        var parts: [String] = []
        if !app.expired.isEmpty {
            parts.append("\(ListFormatter.localizedString(byJoining: app.expired.map(\.label).sorted())) needs reconnecting")
        }
        if missingAccounts > 0 { parts.append("\(missingAccounts) account(s) to connect") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Dever's mark: a D with a calm eye. The same geometry as `docs/brand/dever-mark.svg`,
/// on a 64-unit grid: a panel whose right side is fully round, and an 8-unit hole at (43, 23).
/// Lime on dark, deep green on light (`Soot.lime`), like every action.
struct DeverMark: View {
    var body: some View {
        DeverMarkShape()
            .fill(Soot.lime, style: FillStyle(eoFill: true))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

struct DeverMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 64
        let o = CGPoint(x: rect.midX - 32 * s, y: rect.midY - 32 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var path = Path()
        path.move(to: p(14, 4))
        path.addLine(to: p(32, 4))
        path.addArc(center: p(32, 32), radius: 28 * s, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: p(14, 60))
        path.addArc(center: p(14, 50), radius: 10 * s, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: p(4, 14))
        path.addArc(center: p(14, 14), radius: 10 * s, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: o.x + 35 * s, y: o.y + 15 * s, width: 16 * s, height: 16 * s))
        return path
    }
}

private extension View {
    /// Lets the tinted frame run under the title bar (macOS 15+).
    @ViewBuilder
    func toolbarBackgroundHiddenIfAvailable() -> some View {
        if #available(macOS 15.0, *) {
            self.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }
}

/// Where the open tile sits, so the menu can hang beside it.
private struct RailMenuKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

/// A project tile's menu, in the app's own panel: open, edit, pin, the tools it links, and
/// last, in the negative tone, removing it from Dever (the confirmation stays the same).
private struct RailMenu: View {
    @EnvironmentObject var app: AppState
    let project: Project
    let isCurrent: Bool
    let unread: Int?
    let open: () -> Void
    let edit: () -> Void
    let remove: () -> Void
    let close: () -> Void

    private var slackURL: URL? {
        guard let channel = project.slack, let slack = app.slack else { return nil }
        return URL(string: "https://\(slack.domain).slack.com/archives/\(channel.id)")
    }
    private var linearURL: URL? { project.linear.flatMap { URL(string: $0.url) } }
    private var githubURL: URL? {
        let repos = app.repositories(for: project)
        if repos.count == 1, let repo = repos.first { return URL(string: "https://github.com/\(repo)/pulls") }
        if repos.count > 1 {
            let query = "is:open is:pr " + repos.map { "repo:\($0)" }.joined(separator: " ")
            return URL(string: "https://github.com/pulls?q=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
        }
        return nil
    }

    var body: some View {
        MenuPanel(label: "\(project.name) menu") {
            MenuPanelHead(title: project.name, detail: unread.map { $0 > 0 ? "\($0) unread in Slack" : "Nothing unread" })
            if !isCurrent { MenuPanelRow(symbol: "arrow.right", title: "Open", action: open) }
            MenuPanelRow(symbol: "slider.horizontal.3", title: "Edit project", action: edit)
            MenuPanelRow(symbol: project.favorite == true ? "pin.slash" : "pin",
                         title: project.favorite == true ? "Unpin from top" : "Pin to top") {
                app.setFavorite(project, project.favorite != true)
                close()
            }
            if slackURL != nil || linearURL != nil || githubURL != nil {
                MenuPanelDivider()
                if let url = slackURL { MenuPanelRow(service: .slack, title: "Open in Slack", url: url) }
                if let url = linearURL { MenuPanelRow(service: .linear, title: "Open in Linear", url: url) }
                if let url = githubURL { MenuPanelRow(service: .github, title: "Pull requests on GitHub", url: url) }
            }
            MenuPanelDivider()
            MenuPanelRow(symbol: "trash", title: "Remove from Dever…", destructive: true, action: remove)
        }
        .onExitCommand(perform: close)
    }
}
