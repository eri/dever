import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case accounts
    case project(UUID)
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    @State private var selection: SidebarItem? = .overview
    @State private var showNew = false
    @State private var importSource: ImportSheet.Source?
    @State private var editing: Project?
    @State private var removing: Project?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Overview", systemImage: "square.grid.2x2").tag(SidebarItem.overview)
                    Label("Accounts", systemImage: "person.crop.circle").tag(SidebarItem.accounts)
                        .badge(missingAccounts > 0 ? Text("\(missingAccounts)") : nil)
                }
                Section("Projects") {
                    ForEach(app.projects) { p in
                        let status = p.status(store.snapshots[p.id])
                        Label {
                            Text(p.name).lineLimit(1)
                        } icon: {
                            Image(systemName: status.symbol).foregroundStyle(status.tint)
                        }
                        .help("\(p.name) — \(status.label)")
                        .accessibilityLabel("\(p.name), \(status.label)")
                        .tag(SidebarItem.project(p.id))
                        .contextMenu {
                            Button("Edit links…") { editing = p }
                            Divider()
                            Button("Remove from Dever…", role: .destructive) { removing = p }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("New project…") { showNew = true }.keyboardShortcut("n")
                        Divider()
                        Button("Import from Slack…") { importSource = .slack }.disabled(app.slack == nil)
                        Button("Import from Linear…") { importSource = .linear }.disabled(app.linear == nil)
                    } label: {
                        Label("Add project", systemImage: "plus")
                    }
                    .help("Create or import projects")
                }
            }
        } detail: {
            Group {
                switch selection {
                case .project(let id):
                    if let p = app.projects.first(where: { $0.id == id }) {
                        ProjectDetailView(project: p, edit: { editing = p }).id(p.id)
                    } else {
                        ContentUnavailableView("Project not found", systemImage: "questionmark.folder",
                                               description: Text("It may have been removed. Pick another project in the sidebar."))
                    }
                case .accounts:
                    AccountsView()
                default:
                    OverviewView(open: { selection = .project($0.id) },
                                 newProject: { showNew = true },
                                 importFrom: { importSource = $0 })
                }
            }
            .environment(\.openAccounts, { selection = .accounts })
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

    private var missingAccounts: Int {
        [app.slack == nil, app.linear == nil].filter { $0 }.count
    }
}
