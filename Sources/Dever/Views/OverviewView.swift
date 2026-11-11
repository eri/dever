import SwiftUI

// The home screen answers "what is waiting for me": one list of projects, pinned first, then
// the ones where something waits for you, then the most recently active. A row is the project
// (mark, name, "N for you"), the optional columns from Settings › Overview, and one status at
// the trailing edge: what blocks it, or how much has shipped, or the one link it lacks. Under
// a project with things waiting, those things are listed, one line each, and open inside the
// project's page. A project with nothing waiting stays one line and says what happened last.

struct OverviewView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    let open: (Project) -> Void
    let newProject: () -> Void
    let importFrom: (ImportSheet.Source) -> Void
    /// Opens the project's editor on a step: the one link an incomplete project lacks.
    let link: (Project, ProjectEditorSheet.Step) -> Void

    @State private var search = ""
    @State private var showView = false
    /// The "Add many" menu under the Add project button, drawn inside the window.
    @State private var showMany = false
    /// Rows fade in once, on the page's first appearance.
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One project as the page sees it.
    struct Entry: Identifiable {
        let project: Project
        let status: ProjectStatus
        let snapshot: ProjectSnapshot?
        let waiting: [WaitingItem]
        let last: (text: String, date: Date)?
        var id: UUID { project.id }

        /// Every Linear issue is done: nothing left to ship.
        var isFinished: Bool {
            guard let l = snapshot?.linear, l.total > 0 else { return false }
            return l.done == l.total
        }
    }

    /// A run of rows under one label (or the whole list when not grouped).
    struct Section: Identifiable {
        let id: String
        let label: String?
        let entries: [Entry]
    }

    private var settings: OverviewSettings { app.overview }

    private var entries: [Entry] {
        app.projects.map { p in
            let s = store.snapshots[p.id]
            return Entry(project: p, status: p.status(s), snapshot: s,
                         waiting: s?.waiting(channel: p.slack?.name) ?? [],
                         last: s?.lastActivity(channel: p.slack?.name))
        }
    }

    private var finishedCount: Int { entries.filter(\.isFinished).count }
    private var waitingCount: Int { entries.reduce(0) { $0 + $1.waiting.count } }

    /// The rows after the settings and the search: hidden finished projects out, then the order.
    private var visible: [Entry] {
        entries
            .filter { !settings.hideFinished || !$0.isFinished }
            .filter { search.isEmpty || $0.project.name.localizedCaseInsensitiveContains(search) }
            .sorted(by: ordered)
    }

    /// Pinned first, always. Then, for "For you", the projects where something waits; then the
    /// most recently active; the name settles ties.
    private func ordered(_ a: Entry, _ b: Entry) -> Bool {
        if (a.project.favorite == true) != (b.project.favorite == true) {
            return a.project.favorite == true
        }
        if settings.sort == .forYou, a.waiting.isEmpty != b.waiting.isEmpty {
            return !a.waiting.isEmpty
        }
        if settings.sort != .name {
            let x = a.last?.date, y = b.last?.date
            if x != y { return (x ?? .distantPast) > (y ?? .distantPast) }
        }
        return a.project.name.localizedCaseInsensitiveCompare(b.project.name) == .orderedAscending
    }

    private var sections: [Section] {
        let rows = visible
        switch settings.group {
        case .none:
            return [Section(id: "all", label: nil, entries: rows)]
        case .health:
            let groups = Dictionary(grouping: rows, by: \.status)
            return groups.keys.sorted().map { Section(id: "health:\($0.rawValue)", label: $0.label, entries: groups[$0]!) }
        case .repository:
            return grouped(rows, none: "No repository") { app.repositories(for: $0.project).first }
        case .team:
            return grouped(rows, none: "No team") { $0.snapshot?.linear?.team }
        }
    }

    /// Alphabetical groups, the "none" group last.
    private func grouped(_ rows: [Entry], none: String, by key: (Entry) -> String?) -> [Section] {
        let groups = Dictionary(grouping: rows) { key($0) ?? "" }
        let named = groups.keys.filter { !$0.isEmpty }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var out = named.map { Section(id: "group:\($0)", label: $0, entries: groups[$0]!) }
        if let rest = groups[""] { out.append(Section(id: "group:", label: none, entries: rest)) }
        return out
    }

    /// Changes whenever a row moves or its items change, so the move can animate.
    private var order: String {
        sections.map { "\($0.id)=" + $0.entries.map { "\($0.id.uuidString):\($0.waiting.count)" }.joined(separator: ",") }
            .joined(separator: ";")
    }

    var body: some View {
        Group {
            if app.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        head.zIndex(1)
                        table
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .searchable(text: $search, placement: .toolbar, prompt: "Search projects")
                // A click anywhere else in the window closes the Add-many menu.
                .closesOnOutsideClick(showMany) { Motion.run(Motion.ui, fade: true) { showMany = false } }
            }
        }
        .background(Soot.ground)
        .navigationTitle("Overview")
        .windowTitleHidden()
        // Rows that are already there are read again behind them; only the first load shows.
        .task { if store.isStale { await store.refresh(app, quiet: true) } }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.3)) { appeared = true }
            // Snapshots: DEVER_SNAPSHOT_OVERVIEW_VIEW=1 opens the View popover.
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_OVERVIEW_VIEW"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showView = true }
            }
        }
    }

    // MARK: Head: the title, one quiet line, the actions

    private var head: some View {
        VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Overview").font(.system(size: 28, weight: .semibold)).tracking(-0.8).foregroundStyle(Soot.ink)
                    .accessibilityAddTraits(.isHeader)
                summary
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Button { Task { await store.refresh(app) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ToolbarButton(busy: store.isRefreshing))
                .disabled(store.isRefreshing)
                .keyboardShortcut("r")
                .help("Refresh every project (⌘R)")
                .accessibilityValue(store.isRefreshing ? "Refreshing" : "")
                Button { showView.toggle() } label: {
                    Label("View", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(ToolbarButton())
                .help("Order, grouping, density and columns")
                .accessibilityLabel("View options")
                .popover(isPresented: $showView, arrowEdge: .bottom) {
                    OverviewSettingsView(compact: true)
                        .environmentObject(app)
                        .frame(width: 340)
                        .background(Soot.ground)
                }
                AddProjectControl(add: newProject, addMany: importFrom, showMany: $showMany)
            }
        }
            // Its own row, the page's full width: nothing in it has to be cut.
            ReleaseLine()
        }
    }

    /// How many projects, how many things wait for you (when any), how fresh it is.
    private var summary: some View {
        HStack(spacing: 0) {
            Count(n: app.projects.count, word: app.projects.count == 1 ? "project" : "projects")
            if waitingCount > 0 {
                Text(" · ").accessibilityHidden(true)
                Count(n: waitingCount, word: "for you")
            }
            if settings.hideFinished, finishedCount > 0 {
                Text(" · ").accessibilityHidden(true)
                Count(n: finishedCount, word: "finished, hidden")
            }
            Text(" · ").accessibilityHidden(true)
            freshness
        }
        .font(.system(size: 13))
        .foregroundStyle(Soot.muted)
        .lineLimit(1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: order)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var freshness: some View {
        if store.isRefreshing {
            Text("refreshing")
        } else if let last = store.lastRefresh {
            // Read off the clock, so the age stays true while the page is open; and it is the
            // age of the last refresh that reached the tools, not of the last attempt.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("updated \(last.formatted(.relative(presentation: .named)))"
                     + (store.refreshFailed ? ", couldn't refresh since" : ""))
            }
        } else if store.refreshFailed {
            Text("couldn't load")
        } else {
            Text("loading")
        }
    }

    // MARK: The list

    private var table: some View {
        VStack(spacing: 0) {
            if !settings.shownColumns.isEmpty { ColumnHeader(columns: settings.shownColumns) }
            if visible.isEmpty {
                filteredEmpty
            }
            ForEach(sections) { section in
                if let label = section.label {
                    GroupRow(label: label, count: section.entries.count, density: settings.density)
                        .transition(.opacity)
                }
                ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                    ProjectBlock(entry: entry, columns: settings.shownColumns, density: settings.density,
                                 favorite: Binding(get: { entry.project.favorite == true },
                                                   set: { app.setFavorite(entry.project, $0) }),
                                 open: { open(entry.project) },
                                 openItem: { item in
                                     ProjectFocus.set(item.target, for: entry.project.id)
                                     open(entry.project)
                                 },
                                 link: { link(entry.project, $0) })
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 8)
                        .animation(.easeOut(duration: 0.3).delay(appeared ? 0 : Double(min(index, 12)) * 0.04), value: appeared)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
        .animation(reduceMotion ? nil : Motion.move, value: order)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: settings.density)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Projects")
    }

    /// Everything is filtered out: say by what, and the way back.
    private var filteredEmpty: some View {
        HStack(spacing: 12) {
            if !search.isEmpty {
                Text("No project matches \u{201C}\(search)\u{201D}").foregroundStyle(Soot.muted)
                Button("Clear search") { search = "" }.buttonStyle(SecondaryButton())
            } else {
                Text("Every project is finished and hidden").foregroundStyle(Soot.muted)
                Button("Show finished projects") { app.overview.hideFinished = false }.buttonStyle(SecondaryButton())
            }
            Spacer()
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: settings.density.rowHeight + 8)
    }

    /// No project at all: what a project is, in one line, and the way to add one.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("No projects yet").font(.system(size: 28, weight: .semibold)).tracking(-0.8).foregroundStyle(Soot.ink)
                .accessibilityAddTraits(.isHeader)
            Text("A project joins a Slack channel, a Linear project and a GitHub repository.")
                .font(.system(size: 13)).foregroundStyle(Soot.muted)
                .padding(.top, 4)
            HStack(spacing: 10) {
                Button("Add project", action: newProject).buttonStyle(PrimaryButton())
                if app.slack != nil {
                    Button { importFrom(.slack) } label: { Label("Add many from Slack", systemImage: "number") }
                        .buttonStyle(SecondaryButton())
                }
                if app.linear != nil {
                    Button { importFrom(.linear) } label: { Label("Add many from Linear", systemImage: "checklist") }
                        .buttonStyle(SecondaryButton())
                }
            }
            .padding(.top, 24)
            if app.slack == nil || app.linear == nil {
                Button("Connect Slack and Linear in Settings to start from what you already have") {
                    openSettings()
                }
                .buttonStyle(TertiaryButton(lift: Soot.surface, font: .system(size: 13, weight: .medium)))
                .padding(.top, 16)
                .padding(.leading, -8)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @Environment(\.openSettings) private var openSettings
}

/// A number and its word; the number rolls when it changes.
private struct Count: View {
    let n: Int
    let word: String
    var body: some View {
        HStack(spacing: 3) {
            Text(n, format: .number).monospacedDigit().contentTransition(.numericText(value: Double(n)))
            Text(word)
        }
    }
}

/// "Add project" as the one lime action: one 34px capsule split by a hairline. The left part
/// adds one project, the chevron opens the ways to add many; each part has its own hover and
/// press tone and its own focus ring, drawn inside it so it never crosses the hairline.
private struct AddProjectControl: View {
    @EnvironmentObject var app: AppState
    let add: () -> Void
    let addMany: (ImportSheet.Source) -> Void
    @Binding var showMany: Bool

    private func toggle(_ on: Bool) { Motion.run(Motion.ui, fade: true) { showMany = on } }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold)).accessibilityHidden(true)
                    Text("Add project").font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 12)
            }
            .buttonStyle(PrimarySegment())
            .help("Add a project (⌘N)")
            Rectangle().fill(Soot.limeInk.opacity(0.28)).frame(width: 1, height: 18)
                .accessibilityHidden(true)
            Button { toggle(!showMany) } label: {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(showMany ? 180 : 0))
                    .motion(Motion.ui, value: showMany)
                    .frame(width: 32)
            }
            .buttonStyle(PrimarySegment(open: showMany))
            .help("Add many projects at once")
            .accessibilityLabel("Add many projects")
            .onAppear {
                // Snapshots: DEVER_SNAPSHOT_ADD_MANY=1 opens the menu.
                if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_ADD_MANY"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toggle(true) }
                }
            }
        }
        .foregroundStyle(Soot.limeInk)
        .frame(height: 34)
        .background(Soot.lime, in: RoundedRectangle(cornerRadius: Soot.radius))
        .clipShape(RoundedRectangle(cornerRadius: Soot.radius))
        .keepsMenuOpen()
        // The menu hangs from the button's trailing edge, inside the window, over the table.
        .overlay(alignment: .topTrailing) {
            if showMany {
                AddManyMenu(addMany: { source in toggle(false); addMany(source) }, close: { toggle(false) })
                    .fixedSize()
                    .keepsMenuOpen()
                    .offset(y: 34 + 6)
                    .transition(Motion.pop.combined(with: .offset(y: Motion.reduced ? 0 : -4)))
            }
        }
        .onExitCommand { if showMany { toggle(false) } }
    }
}

/// The ways to add many projects, in the soot language: each tool as a row with its logo, what
/// it brings and an arrow; a tool that is not connected says so and leads to Settings.
private struct AddManyMenu: View {
    @EnvironmentObject var app: AppState
    let addMany: (ImportSheet.Source) -> Void
    let close: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add many").font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            row(.slack, title: "From Slack channels", detail: "One per channel", connected: app.slack != nil)
            row(.linear, title: "From Linear projects", detail: "One per Linear project", connected: app.linear != nil)
        }
        .padding(8)
        .frame(width: 300)
        .background(Soot.ground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Soot.line))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add many projects")
    }

    private func row(_ service: ServiceKind, title: String, detail: String, connected: Bool) -> some View {
        MenuRow(service: service, title: title, detail: connected ? detail : "Connect \(service.label) in Settings",
                connected: connected) {
            if connected {
                addMany(service == .slack ? .slack : .linear)
            } else {
                close()
                openSettings()
            }
        }
    }
}

private struct MenuRow: View {
    let service: ServiceKind
    let title: String
    let detail: String
    let connected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                BrandLogo(service: service, size: 20)
                    .foregroundStyle(Soot.ink)
                    .opacity(connected ? 1 : 0.5)
                    .frame(width: 32, height: 32)
                    .background(Soot.surface, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: connected ? "arrow.right" : "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Soot.muted)
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
        }
        .buttonStyle(RowButton(lift: .surface, radius: Soot.radius))
        .accessibilityLabel("\(title). \(detail)")
    }
}

// MARK: - Rows

/// Column widths and gaps shared by the header and the rows, so every cell lines up.
private enum Grid {
    static let gap: CGFloat = 14
    /// The mark, the name, the "for you" chip; takes what the other columns leave.
    static let nameMin: CGFloat = 180
    /// The status at the trailing edge.
    static let status: CGFloat = 168
    /// The pin slot after it.
    static let pin: CGFloat = 24
    /// Where an item's icon starts: under the project's name.
    static let itemIndent: CGFloat = 12 + 28 + 10

    /// The width the columns, the status and the pin take at a row's trailing edge (gaps
    /// included); the name, and an item's sentence, stop before it.
    static func trailing(_ columns: [OverviewSettings.Column]) -> CGFloat {
        columns.reduce(0) { $0 + $1.width + gap } + status + gap + pin
    }
}

private struct ColumnHeader: View {
    let columns: [OverviewSettings.Column]
    var body: some View {
        HStack(spacing: Grid.gap) {
            Text("Project").frame(minWidth: Grid.nameMin, maxWidth: .infinity, alignment: .leading)
            ForEach(columns) { column in
                Text(column.label).frame(width: column.width, alignment: .leading).help(column.detail)
            }
            Text("Status").frame(width: Grid.status, alignment: .leading)
            Color.clear.frame(width: Grid.pin)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Soot.muted)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .accessibilityHidden(true)
    }
}

/// A group's label and its count, as a quiet row inside the list.
private struct GroupRow: View {
    let label: String
    let count: Int
    let density: OverviewSettings.Density
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.ink)
            Text(count, format: .number).font(.system(size: 12)).foregroundStyle(Soot.muted).monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(height: density == .compact ? 32 : 36)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A project's row and, under it, what waits for you there: three lines at most, then
/// "Show all".
private struct ProjectBlock: View {
    let entry: OverviewView.Entry
    let columns: [OverviewSettings.Column]
    let density: OverviewSettings.Density
    @Binding var favorite: Bool
    let open: () -> Void
    let openItem: (WaitingItem) -> Void
    let link: (ProjectEditorSheet.Step) -> Void
    @State private var expanded = false

    private var items: [WaitingItem] { expanded ? entry.waiting : Array(entry.waiting.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectRow(entry: entry, columns: columns, density: density, favorite: $favorite, open: open, link: link)
            if !entry.waiting.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        ItemRow(item: item, density: density, trailing: Grid.trailing(columns)) { openItem(item) }
                            .transition(Motion.rise)
                    }
                    if entry.waiting.count > 3 {
                        Button(expanded ? "Show fewer" : "Show all \(entry.waiting.count)") {
                            Motion.run(Motion.ui) { expanded.toggle() }
                        }
                        .buttonStyle(TertiaryButton(tint: .muted, lift: Soot.ground, font: .system(size: 12, weight: .semibold), height: 26))
                        .padding(.leading, Grid.itemIndent - 8)
                        .accessibilityLabel(expanded ? "Show fewer for \(entry.project.name)" : "Show all \(entry.waiting.count) for \(entry.project.name)")
                    }
                }
                .padding(.bottom, 6)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Waiting for you in \(entry.project.name)")
            }
        }
    }
}

/// One thing waiting for you: its icon, one sentence, how long ago. Opens it inside Dever.
private struct ItemRow: View {
    let item: WaitingItem
    let density: OverviewSettings.Density
    /// The row's columns and status: the sentence never runs under them.
    let trailing: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.kind == .mention ? Soot.lime : Soot.muted)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(item.text).font(.system(size: 13)).foregroundStyle(Soot.ink).lineLimit(1).truncationMode(.tail)
                Text("· \(Brief.ago(item.date))").font(.system(size: 12)).foregroundStyle(Soot.muted).monospacedDigit()
                    .fixedSize()
                    .help(item.date.formatted(date: .abbreviated, time: .shortened))
                Spacer(minLength: 12)
            }
            .padding(.leading, Grid.itemIndent)
            .padding(.trailing, 12 + trailing)
            .frame(height: density == .compact ? 28 : 32)
        }
        .buttonStyle(RowButton(lift: .ground))
        .help(item.text)
        .accessibilityLabel("\(item.text), \(item.date.formatted(.relative(presentation: .named)))")
        .accessibilityHint(item.kind == .review ? "Opens the pull request in the project" : "Opens the message in the project")
    }
}

private struct ProjectRow: View {
    @EnvironmentObject var app: AppState
    let entry: OverviewView.Entry
    let columns: [OverviewSettings.Column]
    let density: OverviewSettings.Density
    @Binding var favorite: Bool
    let open: () -> Void
    let link: (ProjectEditorSheet.Step) -> Void
    @ObservedObject private var previews = PreviewStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var project: Project { entry.project }
    private var snapshot: ProjectSnapshot? { entry.snapshot }
    private var loaded: Bool { snapshot != nil }

    var body: some View {
        Button(action: open) {
            HStack(spacing: Grid.gap) {
                name.frame(minWidth: Grid.nameMin, maxWidth: .infinity, alignment: .leading)
                // Room for the columns, the status and the pin, drawn on top of the row so a
                // link button and the pin take their own clicks; the rest lets the click through.
                Color.clear.frame(width: Grid.trailing(columns))
            }
            .padding(.horizontal, 12)
            .frame(height: density.rowHeight)
        }
        .buttonStyle(RowButton(lift: .ground))
        .overlay(alignment: .trailing) {
            HStack(spacing: Grid.gap) {
                ForEach(columns) { column in
                    cell(column).frame(width: column.width, alignment: .leading)
                        .allowsHitTesting(false)
                }
                status.frame(width: Grid.status, alignment: .leading)
                    .allowsHitTesting({ if case .link = current { true } else { false } }())
                pin
            }
            .padding(.trailing, 12)
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open \(project.name)", action: open)
            Button(favorite ? "Unpin from top" : "Pin to top") { favorite.toggle() }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: loaded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary)
        .accessibilityHint("Opens the project")
    }

    /// The row in words for VoiceOver: name, what waits, the columns, the status.
    private var summary: String {
        var parts = [project.name + (favorite ? ", pinned" : "")]
        if !entry.waiting.isEmpty { parts.append("\(entry.waiting.count) for you") }
        else if let last = entry.last { parts.append("\(last.text), \(last.date.formatted(.relative(presentation: .named)))") }
        for column in columns {
            switch column {
            case .linear:
                if let d = snapshot?.delivery, d.total > 0 { parts.append("Linear: \(d.shipped) of \(d.total) shipped") }
            case .github:
                if let g = snapshot?.github { parts.append("GitHub: pipeline \(PipelineGlyph.word(g.pipeline)), \(g.openPRs) open pull requests") }
            case .preview:
                if let status = previews.state(for: project)?.status { parts.append("preview \(status.word.lowercased())") }
            case .target:
                if let t = snapshot?.linear?.targetDate { parts.append("due \(t.formatted(.dateTime.day().month(.wide)))") }
            }
        }
        parts.append(statusWords)
        return parts.joined(separator: ", ")
    }

    // MARK: Name

    private var name: some View {
        HStack(spacing: 10) {
            ProjectMark(name: project.name, size: density == .compact ? 24 : 28)
            Text(project.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                .lineLimit(1).truncationMode(.tail).help(project.name)
                .layoutPriority(1)
            if !entry.waiting.isEmpty {
                ForYouChip(count: entry.waiting.count)
                    .transition(Motion.pop)
            } else if let last = entry.last {
                Text("\(last.text) · \(Brief.ago(last.date))")
                    .font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1).truncationMode(.tail)
                    .help("\(last.text), \(last.date.formatted(.relative(presentation: .named)))")
                    .transition(.opacity)
            } else if !loaded {
                Skeleton(width: 96, height: 10)
            }
        }
        .motion(Motion.ui, value: entry.waiting.count)
    }

    /// The pin: always shown for a favourite, otherwise on hover or keyboard focus.
    private var pin: some View {
        PinButton(on: $favorite, visible: favorite || hovering, name: project.name)
    }

    // MARK: Status: what blocks, the one link missing, or how much has shipped

    private enum Status {
        case loading
        case link(ProjectEditorSheet.Step, String)
        case blocked(symbol: String, tint: Color, text: String, help: String)
        case quiet(String)
        case clear
    }

    private var overdue: Bool {
        guard let t = snapshot?.linear?.targetDate, let l = snapshot?.linear else { return false }
        return t < Calendar.current.startOfDay(for: Date()) && l.done < l.total
    }

    /// Where the project stands, in one place: the link it lacks, else what blocks it, else
    /// "On track". Never empty, so a blank never has to be read.
    private var current: Status {
        if project.linear == nil { return .link(.linear, "Link Linear") }
        if project.slack == nil { return .link(.slack, "Link Slack") }
        guard let s = snapshot else { return .loading }
        if let state = s.errors[.linear], state.needsConnecting { return .link(.linear, "Reconnect Linear") }
        if s.github?.pipeline == .failing {
            let repos = s.github?.failingRepositories ?? []
            return .blocked(symbol: "xmark.circle.fill", tint: Theme.negative, text: "CI failing",
                            help: repos.isEmpty ? "The pipeline fails" : "Failing in \(repos.joined(separator: ", "))")
        }
        if previews.state(for: project)?.status?.phase == .failed {
            return .blocked(symbol: "xmark.circle.fill", tint: Theme.negative, text: "Preview failed",
                            help: "The preview of pull request #\(project.previewPullNumber ?? 0) failed to deploy")
        }
        if overdue, let t = s.linear?.targetDate {
            return .blocked(symbol: "exclamationmark.circle.fill", tint: Theme.negative, text: "Past due date",
                            help: "Due \(t.formatted(.dateTime.day().month(.wide))), issues still open")
        }
        if let w = s.github?.longWait {
            return .blocked(symbol: "clock.fill", tint: Theme.chart3, text: "#\(w.number) waiting \(Brief.ago(w.since))",
                            help: "Pull request #\(w.number) has waited for a review since \(w.since.formatted(.relative(presentation: .named)))")
        }
        return .clear
    }

    private var statusWords: String {
        switch current {
        case .loading: "loading"
        case .link(_, let title): "missing a link: \(title)"
        case .blocked(_, _, let text, _): text
        case .quiet(let text): text == "—" ? "" : text
        case .clear: "On track"
        }
    }

    @ViewBuilder private var status: some View {
        switch current {
        case .loading:
            HStack(spacing: 8) { Skeleton(width: 40, height: 6, radius: 3); Skeleton(width: 64, height: 12) }
        case .link(let step, let title):
            linkButton(step, title)
        case .blocked(let symbol, let tint, let text, let help):
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
            }
            .help(help)
            .transition(.opacity)
        case .quiet(let text):
            Text(text).font(.system(size: 13)).foregroundStyle(Soot.muted)
        case .clear:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Soot.lime).accessibilityHidden(true)
                Text("On track").font(.system(size: 13)).foregroundStyle(Soot.ink).lineLimit(1)
            }
            .help("Nothing blocks it: the pipeline passes, the due date holds, no pull request has waited for days")
            .transition(.opacity)
        }
    }

    // MARK: Optional columns

    @ViewBuilder private func cell(_ column: OverviewSettings.Column) -> some View {
        switch column {
        case .linear: linear
        case .github: github
        case .preview: preview
        case .target: target
        }
    }

    @ViewBuilder private var linear: some View {
        if let d = snapshot?.delivery, d.total == 0 {
            Text("No issues").font(.system(size: 13)).foregroundStyle(Soot.muted)
        } else if let d = snapshot?.delivery {
            HStack(spacing: 8) {
                ShipBar(delivery: d).frame(width: 72)
                Text("\(d.shipped)/\(d.total)").font(.system(size: 13)).foregroundStyle(Soot.ink).monospacedDigit()
            }
            .help("\(d.shipped) of \(d.total) issues shipped")
        } else if project.linear == nil {
            Text("Not set up yet").font(.system(size: 13)).foregroundStyle(Soot.muted)
                .help("No Linear project linked: Link Linear, in the status, links one")
        } else if let state = snapshot?.errors[.linear], state.needsConnecting {
            Text("Disconnected").font(.system(size: 13)).foregroundStyle(Soot.muted)
                .help("Linear needs reconnecting: Reconnect Linear, in the status, does it")
        } else if let state = snapshot?.errors[.linear] {
            unavailable(.linear, state)
        } else {
            HStack(spacing: 8) { Skeleton(width: 72, height: 6, radius: 3); Skeleton(width: 32, height: 12) }
        }
    }

    /// The one link a project lacks, as a button that opens the editor on that step.
    private func linkButton(_ step: ProjectEditorSheet.Step, _ title: String) -> some View {
        Button { link(step) } label: {
            Label(title, systemImage: title.hasPrefix("Reconnect") ? "arrow.clockwise" : "link")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(SecondaryButton(size: .panel))
        .fixedSize()
        .help(title.hasPrefix("Reconnect") ? "Reconnect Linear in Settings" : "\(title) to see what is left to ship")
        .transition(.opacity)
    }

    @ViewBuilder private var github: some View {
        if let g = snapshot?.github {
            HStack(spacing: 5) {
                PipelineGlyph(state: g.pipeline)
                Text(PipelineGlyph.word(g.pipeline)).font(.system(size: 13)).foregroundStyle(Soot.ink)
                if g.openPRs > 0 {
                    Text("· \(g.openPRs) PR").font(.system(size: 12)).foregroundStyle(Soot.muted).monospacedDigit()
                }
            }
            .lineLimit(1)
        } else if app.repositories(for: project).isEmpty {
            dash("No repository linked")
        } else if snapshot?.githubNeedsLinear == true {
            Text("Needs Linear").font(.system(size: 13)).foregroundStyle(Soot.muted)
                .help("This project's pull requests are the ones linked to its Linear issues")
        } else if let state = snapshot?.errors[.github] {
            unavailable(.github, state)
        } else {
            Skeleton(width: 72, height: 12)
        }
    }

    @ViewBuilder private var preview: some View {
        if let status = previews.state(for: project)?.status {
            HStack(spacing: 5) {
                PreviewPhaseGlyph(phase: status.phase, health: status.health, size: 12)
                Text(status.word).font(.system(size: 13)).foregroundStyle(Soot.ink).lineLimit(1)
            }
        } else if project.previewPullNumber != nil && !loaded {
            Skeleton(width: 56, height: 12)
        } else {
            dash("No preview followed")
        }
    }

    @ViewBuilder private var target: some View {
        if let t = snapshot?.linear?.targetDate {
            Text(t.formatted(.dateTime.day().month(.abbreviated))).font(.system(size: 13))
                .foregroundStyle(overdue ? Theme.negative : Soot.ink).monospacedDigit().lineLimit(1)
        } else if project.linear == nil || loaded {
            dash("No due date")
        } else {
            Skeleton(width: 44, height: 12)
        }
    }

    /// Missing or not applicable: a quiet dash, never a zero.
    private func dash(_ help: String) -> some View {
        Text(verbatim: "—").font(.system(size: 13)).foregroundStyle(Soot.muted).help(help)
    }

    /// A tool to connect is a quiet chip; a tool that failed says so in a word.
    @ViewBuilder private func unavailable(_ service: ServiceKind, _ state: ServiceState) -> some View {
        switch state {
        case .notConnected: ConnectChip(service: service)
        case .unauthorized: ConnectChip(service: service, verb: "Reconnect")
        case .offline:
            HStack(spacing: 5) {
                Image(systemName: "wifi.slash").font(.system(size: 12)).foregroundStyle(Soot.muted).accessibilityHidden(true)
                Text("Offline").font(.system(size: 13)).foregroundStyle(Soot.muted)
            }
        case .failed(let message):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.negative).accessibilityHidden(true)
                Text("Unreachable").font(.system(size: 13)).foregroundStyle(Soot.ink)
            }
            .help("Couldn't reach \(service.label): \(message)")
        }
    }
}

/// "3 for you": what waits in the project, on the lime that marks things to act on.
private struct ForYouChip: View {
    let count: Int
    var body: some View {
        Text("\(count) for you")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Soot.limeInk)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(count)))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Soot.lime, in: Capsule())
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// The project as its initials on its own tint, as in the rail.
private struct ProjectMark: View {
    let name: String
    var size: CGFloat = 28
    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.75))
            .frame(width: size, height: size)
            .background(PersonTint.color(for: name), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// A project's health as a glyph and its word: shape and colour together, never colour alone.
struct HealthMark: View {
    let status: ProjectStatus
    var body: some View {
        let (symbol, tint): (String, Color) = switch status {
        case .needsAttention: ("exclamationmark.circle.fill", Theme.negative)
        case .quiet: ("moon.fill", Theme.chart3)
        case .onTrack: ("checkmark.circle.fill", Soot.lime)
        case .incomplete: ("circle.dashed", Soot.muted)
        case .notConnected: ("link", Soot.muted)
        case .loading: ("circle.dotted", Soot.muted)
        }
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(status.label).font(.system(size: 13, weight: status == .needsAttention ? .medium : .regular))
                .foregroundStyle(Soot.ink).lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Health: \(status.label)")
    }
}

/// A pin on the row's trailing edge: a button of its own, 28px, lime when on.
private struct PinButton: View {
    @Binding var on: Bool
    let visible: Bool
    let name: String
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        Button { on.toggle() } label: {
            Image(systemName: on ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Soot.lime : Soot.muted)
                .frame(width: 28, height: 28)
                .background(hovering ? Soot.surface : Color.clear, in: Circle())
        }
        .buttonStyle(IconButton(fill: nil))
        .focused($focused)
        .opacity(visible || hovering || focused ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: visible || hovering)
        .onHover { hovering = $0 }
        .help(on ? "Unpin \(name) from the top" : "Pin \(name) to the top")
        .accessibilityLabel(on ? "Unpin \(name)" : "Pin \(name) to the top")
    }
}

/// Issues shipped as a bar: the same count as the `shipped/total` beside it (done in Linear,
/// or with a merged pull request whatever the ticket says). Fills on first appearance and on
/// each change.
private struct ShipBar: View {
    let delivery: Delivery
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let fraction = CGFloat(delivery.shipped) / CGFloat(max(delivery.total, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.empty)
                Capsule().fill(delivery.shipped == delivery.total ? Soot.lime : Theme.chart1)
                    .frame(width: shown ? max(fraction > 0 ? 6 : 0, geo.size.width * fraction) : 0)
            }
        }
        .frame(height: 6)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.9), value: delivery)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.9), value: shown)
        .onAppear { shown = true }
        .accessibilityHidden(true)
    }
}

extension PipelineGlyph {
    /// The word beside the glyph.
    static func word(_ state: ProjectSnapshot.PipelineState) -> String {
        switch state {
        case .passing: "passing"
        case .failing: "failing"
        case .running: "running"
        case .unknown: "no runs"
        }
    }
}

/// Short relative time for a cell: "2h", "3d", "5w".
enum Brief {
    static func ago(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        if s < 7 * 86_400 { return "\(Int(s / 86_400))d" }
        if s < 60 * 86_400 { return "\(Int(s / (7 * 86_400)))w" }
        return "\(Int(s / (30 * 86_400)))mo"
    }
}

// MARK: - Release line

/// Where the code stands, under the title: what went to production last, what landed on
/// staging last (with its checks), and the release waiting to go. One line, three links;
/// hovering one shows what it is about, and which checks fail.
private struct ReleaseLine: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    @ObservedObject private var release = ReleaseStore.shared
    /// The part whose card shows, and the pending open or close of that card.
    @State private var shown: Part?
    @State private var pending: Task<Void, Never>?

    enum Part: Hashable { case prod, staging, next }

    var body: some View {
        Group {
            if let s = release.state {
                HStack(spacing: 6) {
                    if let p = s.production {
                        part(.prod, symbol: "checkmark.seal.fill", tint: Soot.lime, title: "Prod",
                             detail: "\(Brief.ago(p.date)) ago · \(p.author)", checks: nil, url: p.url) {
                            ReleaseCard(heading: "#\(p.number) \(p.title)",
                                        line: "Merged into \(s.productionBranch) \(p.date.formatted(.relative(presentation: .named))) by \(p.author)",
                                        checks: [], url: p.url)
                        }
                    }
                    if let st = s.staging {
                        part(.staging, symbol: "testtube.2", tint: Theme.chart2, title: "Staging",
                             detail: "\(Brief.ago(st.date)) ago · \(st.author)", checks: s.stagingChecks, url: st.url) {
                            ReleaseCard(heading: "#\(st.number) \(st.title)",
                                        line: "Merged into \(s.stagingBranch ?? "staging") \(st.date.formatted(.relative(presentation: .named))) by \(st.author)",
                                        checks: s.stagingCheckList, url: st.url)
                        }
                    }
                    if let n = s.next {
                        part(.next, symbol: "arrow.up.forward.circle.fill", tint: Soot.muted, title: "Next prod",
                             detail: "#\(n.number) · open \(Brief.ago(n.opened))", checks: n.checks, url: n.url) {
                            ReleaseCard(heading: "#\(n.number) \(n.title)",
                                        line: "Into \(s.productionBranch), opened \(n.opened.formatted(.relative(presentation: .named))) by \(n.author)",
                                        checks: n.checkList, url: n.url)
                        }
                    }
                    if release.failed, let at = release.loadedAt {
                        Text("as of \(at.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 12)).foregroundStyle(Soot.muted)
                            .padding(.leading, 4)
                    }
                }
                .padding(.leading, -8)
                .transition(.opacity)
            } else if ReleaseStore.repository(app) != nil, app.github != nil, release.loadedAt == nil, !release.failed {
                Skeleton(width: 320, height: 12).padding(.vertical, 8)
            }
        }
        .motion(Motion.ui, fade: true, value: release.state)
        .task(id: store.lastRefresh) { await release.refresh(app) }
        .onAppear {
            // Snapshots: DEVER_SNAPSHOT_RELEASE_CARD=prod|staging|next opens that part's card.
            switch ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_RELEASE_CARD"] {
            case "prod": shown = .prod
            case "staging": shown = .staging
            case "next": shown = .next
            default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Releases of \(release.state?.repository ?? "the repository")")
    }

    /// Hovering a part or its card keeps the card; leaving both closes it a moment later.
    private func hover(_ part: Part, _ inside: Bool) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: inside ? 250_000_000 : 180_000_000)
            guard !Task.isCancelled else { return }
            Motion.run(Motion.ui, fade: true) { shown = inside ? part : (shown == part ? nil : shown) }
        }
    }

    private func part<Card: View>(_ id: Part, symbol: String, tint: Color, title: String, detail: String,
                                  checks: ProjectSnapshot.PipelineState?, url: URL,
                                  @ViewBuilder card: @escaping () -> Card) -> some View {
        HoverLink(destination: url, hoverTint: Soot.surface) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(Soot.muted).monospacedDigit()
                if let checks, checks != .unknown { PipelineGlyph(state: checks) }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .simultaneousGesture(TapGesture().onEnded { release.opened() })
        .onHover { hover(id, $0) }
        .overlay(alignment: .topLeading) {
            if shown == id {
                card()
                    .onHover { hover(id, $0) }
                    .offset(x: 0, y: 32)
                    .transition(Motion.pop.combined(with: .offset(y: Motion.reduced ? 0 : -4)))
            }
        }
        .zIndex(shown == id ? 1 : 0)
        .accessibilityLabel("\(title): \(detail)" + (checks.map { $0 == .unknown ? "" : ", checks \(PipelineGlyph.word($0))" } ?? "") + ". Opens on GitHub")
    }
}

/// The card under a part of the release line: the pull request, one line on where and when,
/// the checks that fail (and those still running), and the way to GitHub.
private struct ReleaseCard: View {
    let heading: String
    let line: String
    let checks: [ReleaseStore.Check]
    let url: URL

    private var failing: [ReleaseStore.Check] { checks.filter { $0.state == .failing } }
    private var running: [ReleaseStore.Check] { checks.filter { $0.state == .running } }
    private var passing: Int { checks.filter { $0.state == .passing }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(heading).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink).lineLimit(2)
                Text(line).font(.system(size: 12)).foregroundStyle(Soot.muted)
            }
            if !checks.isEmpty {
                Rectangle().fill(Soot.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach((failing + running).prefix(6)) { check in
                        HStack(spacing: 6) {
                            PipelineGlyph(state: check.state)
                            if let u = check.url {
                                Link(check.name, destination: u)
                                    .buttonStyle(TertiaryButton(tint: .ink, lift: Soot.surface, font: .system(size: 12), height: 22))
                                    .padding(.leading, -8)
                            } else {
                                Text(check.name).font(.system(size: 12)).foregroundStyle(Soot.ink)
                            }
                        }
                        .lineLimit(1)
                    }
                    if failing.count + running.count > 6 {
                        Text("and \(failing.count + running.count - 6) more").font(.system(size: 12)).foregroundStyle(Soot.muted)
                    }
                    Text(summary).font(.system(size: 12)).foregroundStyle(Soot.muted)
                }
            }
            ExternalLink("Open on GitHub", destination: url, lift: Soot.surface)
                .padding(.leading, -8)
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(Soot.ground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Soot.line))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        .fixedSize()
    }

    private var summary: String {
        var parts: [String] = []
        if !failing.isEmpty { parts.append("\(failing.count) failing") }
        if !running.isEmpty { parts.append("\(running.count) running") }
        parts.append("\(passing) passing")
        return parts.joined(separator: " · ")
    }
}
