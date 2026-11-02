import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case accounts
    case project(UUID)
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    @State private var selection: SidebarItem = .overview
    @State private var showNew = false
    @State private var importSource: ImportSheet.Source?
    @State private var editing: Project?
    @State private var removing: Project?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: Theme.sidebarWidth, max: 280)
        } detail: {
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
                case .accounts:
                    AccountsView()
                case .overview:
                    OverviewView(open: { selection = .project($0.id) },
                                 newProject: { showNew = true },
                                 importFrom: { importSource = $0 })
                }
            }
            .environment(\.openAccounts, { selection = .accounts })
            .background(Theme.frame)
            .toolbarBackgroundHiddenIfAvailable()
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
        .onReceive(NotificationCenter.default.publisher(for: .showScreen)) { note in
            if let item = note.object as? SidebarItem { selection = item }
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

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            productHeader
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    navRow("Overview", symbol: "square.grid.2x2", item: .overview)
                    HStack {
                        Text("Projects").font(Theme.small).foregroundStyle(Theme.muted)
                        Spacer()
                        addMenu
                    }
                    .padding(.leading, 8)
                    .padding(.top, 24)
                    .padding(.bottom, 6)
                    ForEach(app.projects) { p in projectRow(p) }
                    if app.projects.isEmpty {
                        Text("No projects yet").font(Theme.small).foregroundStyle(Theme.muted).padding(.leading, 8)
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            navRow("Accounts", symbol: "person.crop.circle", item: .accounts,
                   trailing: missingAccounts > 0 ? "\(missingAccounts) to connect" : nil)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.frame)
    }

    /// The product's mark and the scope it is looking at.
    private var productHeader: some View {
        HStack(spacing: 10) {
            DeverMark().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Dever").font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Text(scope).font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var scope: String {
        app.linear?.account.orgName ?? app.slack?.teamName ?? "No workspace connected"
    }

    private func navRow(_ title: String, symbol: String, item: SidebarItem, trailing: String? = nil) -> some View {
        Button { selection = item } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 16).foregroundStyle(Theme.muted)
                Text(title).foregroundStyle(Theme.text)
                Spacer(minLength: 4)
                if let trailing { Text(trailing).font(Theme.small).foregroundStyle(Theme.muted) }
            }
            .font(Theme.body)
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(selection == item ? Theme.active : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == item ? .isSelected : [])
    }

    private func projectRow(_ p: Project) -> some View {
        let status = p.status(store.snapshots[p.id])
        let item = SidebarItem.project(p.id)
        return Button { selection = item } label: {
            HStack(spacing: 10) {
                Image(systemName: status.symbol).foregroundStyle(status.tint).frame(width: 16).imageScale(.small)
                Text(p.name).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 4)
            }
            .font(Theme.body)
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(selection == item ? Theme.active : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(p.name) — \(status.label)")
        .accessibilityLabel("\(p.name), \(status.label)")
        .accessibilityAddTraits(selection == item ? .isSelected : [])
        .contextMenu {
            Button("Edit links…") { editing = p }
            Divider()
            Button("Remove from Dever…", role: .destructive) { removing = p }
        }
    }

    private var addMenu: some View {
        Menu {
            Button("New project…") { showNew = true }.keyboardShortcut("n")
            Divider()
            Button("Import from Slack…") { importSource = .slack }.disabled(app.slack == nil)
            Button("Import from Linear…") { importSource = .linear }.disabled(app.linear == nil)
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
