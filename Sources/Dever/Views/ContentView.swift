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
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
    @State private var showOnboarding = false
    @State private var githubSheet = false

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
                                 importFrom: { importSource = $0 })
                }
            }
            .environment(\.openSettings, { selection = .settings })
            .background(Theme.frame)
            .toolbarBackgroundHiddenIfAvailable()
            .navigationDestination(for: IssueRoute.self) { IssueDetailView(route: $0) }
            }
        }
        .onChange(of: selection) { _, _ in path = NavigationPath() }
        .onReceive(NotificationCenter.default.publisher(for: .openIssue)) { note in
            if let route = note.object as? IssueRoute { path.append(route) }
        }
        .task {
            store.startAutoRefresh(app)
            // Ask once, when there is something to be notified about.
            if !app.projects.isEmpty, await Notifier.shared.authorizationStatus() == .notDetermined {
                _ = await Notifier.shared.requestAuthorization()
            }
        }
        .task {
            if let dir = Snapshotter.directory { await Snapshotter.run(in: dir, projects: app.projects) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSheet)) { note in
            importSource = nil; showNew = false; githubSheet = false
            switch note.object as? String {
            case "import-slack": importSource = .slack
            case "import-linear": importSource = .linear
            case "new-project": showNew = true
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

    // MARK: Rail

    /// A slim rail instead of a sidebar: the projects are a handful of tiles, so they don't
    /// need 240px. Every icon has a tooltip and an accessible name.
    private var rail: some View {
        VStack(spacing: 6) {
            DeverMark().frame(width: 22, height: 22)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .help("Dever · \(scope)")
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(FocusOutline(radius: 10))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A project as its initials on its own tint, with a dot when it needs attention.
    private func projectTile(_ p: Project) -> some View {
        let status = p.status(store.snapshots[p.id])
        let item = SidebarItem.project(p.id)
        let on = selection == item
        let initials = p.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return Button { selection = item } label: {
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
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Theme.text : .clear, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(FocusOutline(radius: 12))
        .help("\(p.name) — \(status.label)")
        .accessibilityLabel("\(p.name), \(status.label)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .contextMenu {
            Button("Edit links…") { editing = p }
            Divider()
            Button("Remove from Dever…", role: .destructive) { removing = p }
        }
    }

    /// You, opening Settings; a dot while an account still needs connecting.
    private var userTile: some View {
        let on = selection == .settings
        let name = displayName.isEmpty ? "Settings" : displayName
        return Button { selection = .settings } label: {
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.chart1)
                .frame(width: 32, height: 32)
                .background(Theme.chart1.opacity(0.15), in: Circle())
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(FocusOutline(radius: 20))
        .help(accountsHint.map { "Settings — \($0)" } ?? "Settings")
        .accessibilityLabel(accountsHint.map { "Settings, \($0)" } ?? "Settings")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var addMenu: some View {
        Menu {
            Button("Add project…") { showNew = true }.keyboardShortcut("n")
            Divider()
            Button("From Slack channels…") { importSource = .slack }.disabled(app.slack == nil)
            Button("From Linear projects…") { importSource = .linear }.disabled(app.linear == nil)
        } label: {
            Image(systemName: "plus").foregroundStyle(Theme.muted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Create or import projects")
        .accessibilityLabel("Add project")
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

/// Dever's mark: three bars of a delivery strip, shipped to to-do.
struct DeverMark: View {
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let bar = h * 0.22
            VStack(alignment: .leading, spacing: (h - bar * 3) / 2) {
                Capsule().fill(Theme.chart1).frame(width: geo.size.width, height: bar)
                Capsule().fill(Theme.chart1.opacity(0.6)).frame(width: geo.size.width * 0.72, height: bar)
                Capsule().fill(Theme.chart1.opacity(0.3)).frame(width: geo.size.width * 0.44, height: bar)
            }
        }
        .accessibilityHidden(true)
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
