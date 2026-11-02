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

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Overview", systemImage: "square.grid.2x2").tag(SidebarItem.overview)
                    Label("Accounts", systemImage: "person.crop.circle.badge.checkmark").tag(SidebarItem.accounts)
                }
                Section("Projects") {
                    ForEach(app.projects) { p in
                        HStack {
                            Circle().fill(dotColor(p)).frame(width: 7, height: 7)
                            Text(p.name)
                        }
                        .tag(SidebarItem.project(p.id))
                        .contextMenu {
                            Button("Edit links…") { editing = p }
                            Button("Remove from Dever", role: .destructive) { app.delete(p) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("New project…") { showNew = true }
                        Divider()
                        Button("Import from Slack…") { importSource = .slack }.disabled(app.slack == nil)
                        Button("Import from Linear…") { importSource = .linear }.disabled(app.linear == nil)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        } detail: {
            switch selection {
            case .project(let id):
                if let p = app.projects.first(where: { $0.id == id }) {
                    ProjectDetailView(project: p, edit: { editing = p }).id(p.id)
                } else {
                    ContentUnavailableView("Project not found", systemImage: "questionmark.folder")
                }
            case .accounts:
                AccountsView()
            default:
                OverviewView(open: { selection = .project($0.id) },
                             newProject: { showNew = true },
                             importFrom: { importSource = $0 })
            }
        }
        .sheet(isPresented: $showNew) { ProjectEditorSheet() }
        .sheet(item: $importSource) { ImportSheet(source: $0) }
        .sheet(item: $editing) { ProjectEditorSheet(project: $0, isNew: false) }
    }

    private func dotColor(_ p: Project) -> Color {
        StatusPill(status: p.status(store.snapshots[p.id])).color
    }
}
