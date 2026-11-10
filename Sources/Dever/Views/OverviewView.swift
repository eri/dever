import SwiftUI

// The home screen in the onboarding's spirit: one table of projects, every row the same
// shape (mark and name, then one cell per tool, the preview, the target date, the health),
// a quiet line of counts above it, and the two actions on the right. Order, grouping,
// density and columns come from Settings › Overview (`AppState.overview`), never from
// controls scattered on the page; the small View button opens those same settings.

struct OverviewView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    let open: (Project) -> Void
    let newProject: () -> Void
    let importFrom: (ImportSheet.Source) -> Void

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
        app.projects.map { Entry(project: $0, status: $0.status(store.snapshots[$0.id]), snapshot: store.snapshots[$0.id]) }
    }

    private var finishedCount: Int { entries.filter(\.isFinished).count }

    /// The rows after the settings and the search: hidden finished projects out, favourites
    /// first, then the chosen order.
    private var visible: [Entry] {
        entries
            .filter { !settings.hideFinished || !$0.isFinished }
            .filter { search.isEmpty || $0.project.name.localizedCaseInsensitiveContains(search) }
            .sorted(by: ordered)
    }

    private func ordered(_ a: Entry, _ b: Entry) -> Bool {
        if settings.pinFavourites, (a.project.favorite == true) != (b.project.favorite == true) {
            return a.project.favorite == true
        }
        switch settings.sort {
        case .name:
            break
        case .activity:
            let x = a.snapshot?.slack?.lastActivity, y = b.snapshot?.slack?.lastActivity
            if x != y { return (x ?? .distantPast) > (y ?? .distantPast) }
        case .health:
            if a.status != b.status { return a.status < b.status }
        case .targetDate:
            let x = a.snapshot?.linear?.targetDate, y = b.snapshot?.linear?.targetDate
            if x != y { return (x ?? .distantFuture) < (y ?? .distantFuture) }
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

    /// Changes whenever a row moves, so the move can animate.
    private var order: String {
        sections.map { "\($0.id)=" + $0.entries.map(\.id.uuidString).joined(separator: ",") }.joined(separator: ";")
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
                            .overlay {
                                // A click anywhere under the open menu closes it.
                                if showMany {
                                    Color.clear.contentShape(Rectangle())
                                        .onTapGesture { Motion.run(Motion.ui, fade: true) { showMany = false } }
                                }
                            }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .searchable(text: $search, placement: .toolbar, prompt: "Search projects")
            }
        }
        .background(Soot.ground)
        .navigationTitle("Overview")
        .windowTitleHidden()
        .task { if store.isStale { await store.refresh(app) } }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.3)) { appeared = true }
            // Snapshots: DEVER_SNAPSHOT_OVERVIEW_VIEW=1 opens the View popover.
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_OVERVIEW_VIEW"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showView = true }
            }
        }
    }

    // MARK: Head: the title, the counts, the actions

    private var head: some View {
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
    }

    /// The counts in one quiet line: how many projects, how many in each state that has any,
    /// and how fresh the numbers are. Each number counts up or down as it changes.
    private var summary: some View {
        HStack(spacing: 0) {
            Count(n: app.projects.count, word: app.projects.count == 1 ? "project" : "projects")
            ForEach([ProjectStatus.needsAttention, .quiet, .incomplete, .notConnected, .onTrack], id: \.self) { status in
                let n = entries.filter { $0.status == status }.count
                if n > 0 {
                    Text(" · ").accessibilityHidden(true)
                    Count(n: n, word: status.label.lowercased())
                }
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
            Text("updated \(last.formatted(.relative(presentation: .named)))")
        } else {
            Text("loading")
        }
    }

    // MARK: The table

    private var table: some View {
        VStack(spacing: 0) {
            ColumnHeader(columns: settings.shownColumns)
            if visible.isEmpty {
                filteredEmpty
            }
            ForEach(sections) { section in
                if let label = section.label {
                    GroupRow(label: label, count: section.entries.count, density: settings.density)
                        .transition(.opacity)
                }
                ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                    ProjectRow(entry: entry, columns: settings.shownColumns, density: settings.density,
                               favorite: Binding(get: { entry.project.favorite == true },
                                                 set: { app.setFavorite(entry.project, $0) }),
                               open: { open(entry.project) })
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
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: order)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: settings.density)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Projects")
    }

    /// Everything is filtered out: say by what, and the way back.
    private var filteredEmpty: some View {
        HStack(spacing: 12) {
            if !search.isEmpty {
                Text("No project matches \u{201C}\(search)\u{201D}").foregroundStyle(Soot.muted)
                Button("Clear search") { search = "" }.buttonStyle(QuietButton())
            } else {
                Text("Every project is finished and hidden").foregroundStyle(Soot.muted)
                Button("Show finished projects") { app.overview.hideFinished = false }.buttonStyle(QuietButton())
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
                Button("Add project", action: newProject).buttonStyle(LimeButton())
                if app.slack != nil {
                    Button { importFrom(.slack) } label: { Label("Add many from Slack", systemImage: "number") }
                        .buttonStyle(QuietButton())
                }
                if app.linear != nil {
                    Button { importFrom(.linear) } label: { Label("Add many from Linear", systemImage: "checklist") }
                        .buttonStyle(QuietButton())
                }
            }
            .padding(.top, 24)
            if app.slack == nil || app.linear == nil {
                Button("Connect Slack and Linear in Settings to start from what you already have") {
                    openSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13)).foregroundStyle(Soot.lime)
                .modifier(FocusOutline(radius: 4))
                .padding(.top, 16)
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
            .buttonStyle(LimeSegment())
            .help("Add a project (⌘N)")
            Rectangle().fill(Soot.limeInk.opacity(0.28)).frame(width: 1, height: 18)
                .accessibilityHidden(true)
            Button { toggle(!showMany) } label: {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(showMany ? 180 : 0))
                    .motion(Motion.ui, value: showMany)
                    .frame(width: 32)
            }
            .buttonStyle(LimeSegment(open: showMany))
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
        // The menu hangs from the button's trailing edge, inside the window, over the table.
        .overlay(alignment: .topTrailing) {
            if showMany {
                AddManyMenu(addMany: { source in toggle(false); addMany(source) }, close: { toggle(false) })
                    .fixedSize()
                    .offset(y: 34 + 6)
                    .transition(Motion.pop.combined(with: .offset(y: Motion.reduced ? 0 : -4)))
            }
        }
        .onExitCommand { if showMany { toggle(false) } }
    }
}

/// One part of a split lime button: a tone on hover and press, the focus ring inside it.
private struct LimeSegment: ButtonStyle {
    var open = false
    func makeBody(configuration: Configuration) -> some View {
        LimeSegmentBody(configuration: configuration, open: open)
    }
}

private struct LimeSegmentBody: View {
    let configuration: ButtonStyle.Configuration
    let open: Bool
    @State private var hovering = false
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .frame(maxHeight: .infinity)
            .background(Soot.limeInk.opacity(configuration.isPressed ? 0.16 : hovering || open ? 0.08 : 0))
            .overlay(RoundedRectangle(cornerRadius: Soot.radius - 2).strokeBorder(Soot.limeInk, lineWidth: 2)
                .padding(2).opacity(focused ? 1 : 0))
            .contentShape(Rectangle())
            .motion(Motion.quick, fade: true, value: hovering)
            .motion(Motion.quick, fade: true, value: open)
            .onHover { hovering = $0 }
            .handCursor()
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
    @State private var hovering = false

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
                    .foregroundStyle(hovering && connected ? Soot.limeInk : Soot.muted)
                    .frame(width: 26, height: 26)
                    .background(hovering && connected ? Soot.lime : Color.clear, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(hovering ? Soot.surface : Color.clear, in: RoundedRectangle(cornerRadius: Soot.radius))
            .contentShape(RoundedRectangle(cornerRadius: Soot.radius))
        }
        .buttonStyle(.plain)
        .modifier(FocusOutline(radius: Soot.radius))
        .motion(Motion.quick, fade: true, value: hovering)
        .onHover { hovering = $0 }
        .handCursor()
        .accessibilityLabel("\(title). \(detail)")
    }
}

// MARK: - Rows

/// Column widths and gaps shared by the header and the rows, so every cell lines up.
private enum Grid {
    static let gap: CGFloat = 14
    /// The mark, the name and the tool logos; takes what the other columns leave.
    static let nameMin: CGFloat = 140
    /// The pin slot at the trailing edge.
    static let pin: CGFloat = 24
}

private struct ColumnHeader: View {
    let columns: [OverviewSettings.Column]
    var body: some View {
        HStack(spacing: Grid.gap) {
            Text("Project").frame(minWidth: Grid.nameMin, maxWidth: .infinity, alignment: .leading)
            ForEach(columns) { column in
                Text(column.label).frame(width: column.width, alignment: .leading).help(column.detail)
            }
            Color.clear.frame(width: Grid.pin)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Soot.muted)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .accessibilityHidden(true)
    }
}

/// A group's label and its count, as a quiet row inside the table.
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

private struct ProjectRow: View {
    @EnvironmentObject var app: AppState
    let entry: OverviewView.Entry
    let columns: [OverviewSettings.Column]
    let density: OverviewSettings.Density
    @Binding var favorite: Bool
    let open: () -> Void
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
                ForEach(columns) { column in
                    cell(column).frame(width: column.width, alignment: .leading)
                }
                // Room for the pin, which sits on top of the row so it takes its own click.
                Color.clear.frame(width: Grid.pin)
            }
            .padding(.horizontal, 12)
            .frame(height: density.rowHeight)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background(hovering ? Soot.ground.opacity(0.7) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeOut(duration: 0.15), value: hovering)
        .overlay(alignment: .trailing) { pin.padding(.trailing, 12) }
        .modifier(FocusOutline(radius: 8))
        .onHover { hovering = $0 }
        .handCursor()
        .contextMenu {
            Button("Open \(project.name)", action: open)
            Button(favorite ? "Unpin from top" : "Pin to top") { favorite.toggle() }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: loaded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityHint("Opens the project")
    }

    /// The row in words, in column order, for VoiceOver.
    private var summary: String {
        var parts = [project.name + (favorite ? ", pinned" : "")]
        for column in columns {
            switch column {
            case .slack:
                if let s = snapshot?.slack {
                    parts.append("Slack: \(s.messagesThisWeek) messages this week" + (s.lastActivity.map { ", last \($0.formatted(.relative(presentation: .named)))" } ?? ""))
                } else if project.slack == nil { parts.append("no Slack channel") }
            case .linear:
                if let d = snapshot?.delivery { parts.append("Linear: \(d.shipped) of \(d.total) shipped") }
                else if project.linear == nil { parts.append("no Linear project") }
            case .github:
                if let g = snapshot?.github { parts.append("GitHub: pipeline \(PipelineGlyph.word(g.pipeline)), \(g.openPRs) open pull requests") }
            case .preview:
                if let phase = previews.state(for: project)?.status?.phase { parts.append("preview \(phase.word.lowercased())") }
            case .target:
                if let t = snapshot?.linear?.targetDate {
                    parts.append("due \(t.formatted(.dateTime.day().month(.wide)))" + (overdue ? ", past" : ""))
                }
            case .health:
                parts.append(entry.status.label)
            }
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Name

    private var name: some View {
        HStack(spacing: 10) {
            ProjectMark(name: project.name, size: density == .compact ? 24 : 28)
            Text(project.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                .lineLimit(1).truncationMode(.tail).help(project.name)
            HStack(spacing: 5) {
                if project.slack != nil { BrandLogo(service: .slack, size: 11).foregroundStyle(Soot.muted) }
                if project.linear != nil { BrandLogo(service: .linear, size: 11).foregroundStyle(Soot.muted) }
                if !app.repositories(for: project).isEmpty { BrandLogo(service: .github, size: 11).foregroundStyle(Soot.muted) }
            }
            .accessibilityHidden(true)
            .padding(.leading, 2)
        }
    }

    /// The pin: always shown for a favourite, otherwise on hover or keyboard focus.
    private var pin: some View {
        PinButton(on: $favorite, visible: favorite || hovering, name: project.name)
    }

    // MARK: Cells

    @ViewBuilder private func cell(_ column: OverviewSettings.Column) -> some View {
        switch column {
        case .slack: slack
        case .linear: linear
        case .github: github
        case .preview: preview
        case .target: target
        case .health: health
        }
    }

    @ViewBuilder private var slack: some View {
        if let s = snapshot?.slack {
            HStack(spacing: 4) {
                if s.messagesThisWeek == 0 {
                    Text("None").font(.system(size: 13)).foregroundStyle(Soot.muted)
                } else {
                    Text(s.messagesThisWeek, format: .number).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(s.messagesThisWeek)))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: s.messagesThisWeek)
                    Text(s.messagesThisWeek == 1 ? "message" : "messages").font(.system(size: 13)).foregroundStyle(Soot.muted)
                }
            }
            .lineLimit(1)
            .help("Messages in the channel over the last 7 days"
                  + (s.lastActivity.map { " · last one \($0.formatted(.relative(presentation: .named)))" } ?? ""))
            .transition(.opacity)
        } else if project.slack == nil {
            dash("No Slack channel linked")
        } else if let state = snapshot?.errors[.slack] {
            unavailable(.slack, state)
        } else {
            Skeleton(width: 80, height: 12)
        }
    }

    @ViewBuilder private var linear: some View {
        if let d = snapshot?.delivery, d.total == 0 {
            Text("No issues").font(.system(size: 13)).foregroundStyle(Soot.muted)
                .help("The Linear project has no issues yet")
                .transition(.opacity)
        } else if let d = snapshot?.delivery {
            HStack(spacing: 8) {
                ShipBar(delivery: d).frame(width: 72)
                Text("\(d.shipped)/\(d.total)").font(.system(size: 13)).foregroundStyle(Soot.ink).monospacedDigit()
                    .contentTransition(.numericText(value: Double(d.shipped)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: d.shipped)
                    .help("\(d.shipped) of \(d.total) issues shipped" + (d.merged > 0 ? " · \(d.merged) merged but still in progress in Linear" : ""))
            }
            .transition(.opacity)
        } else if project.linear == nil {
            dash("No Linear project linked")
        } else if let state = snapshot?.errors[.linear] {
            unavailable(.linear, state)
        } else {
            HStack(spacing: 8) { Skeleton(width: 72, height: 6, radius: 3); Skeleton(width: 32, height: 12) }
        }
    }

    @ViewBuilder private var github: some View {
        if let g = snapshot?.github {
            HStack(spacing: 5) {
                PipelineGlyph(state: g.pipeline)
                Text(PipelineGlyph.word(g.pipeline)).font(.system(size: 13)).foregroundStyle(Soot.ink)
                if g.openPRs > 0 {
                    Text("· \(g.openPRs) PR").font(.system(size: 12)).foregroundStyle(Soot.muted).monospacedDigit()
                        .help("\(g.openPRs) open pull requests")
                }
            }
            .lineLimit(1)
            .transition(.opacity)
        } else if app.repositories(for: project).isEmpty {
            dash("No repository linked")
        } else if let state = snapshot?.errors[.github] {
            unavailable(.github, state)
        } else {
            Skeleton(width: 72, height: 12)
        }
    }

    @ViewBuilder private var preview: some View {
        if let phase = previews.state(for: project)?.status?.phase {
            HStack(spacing: 5) {
                PreviewPhaseGlyph(phase: phase, size: 12)
                Text(phase.word).font(.system(size: 13)).foregroundStyle(Soot.ink).lineLimit(1)
            }
            .help("Preview of pull request #\(project.previewPullNumber ?? 0): \(phase.word.lowercased())")
            .transition(.opacity)
        } else if project.previewPullNumber == nil || !loaded {
            if project.previewPullNumber != nil { Skeleton(width: 56, height: 12) } else { dash("No preview followed") }
        } else {
            dash("No preview followed")
        }
    }

    private var overdue: Bool {
        guard let t = snapshot?.linear?.targetDate, let l = snapshot?.linear else { return false }
        return t < Calendar.current.startOfDay(for: Date()) && l.done < l.total
    }

    @ViewBuilder private var target: some View {
        if let t = snapshot?.linear?.targetDate {
            HStack(spacing: 5) {
                if overdue {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.negative).accessibilityHidden(true)
                }
                Text(t.formatted(.dateTime.day().month(.abbreviated))).font(.system(size: 13))
                    .foregroundStyle(overdue ? Theme.negative : Soot.ink).monospacedDigit().lineLimit(1)
            }
            .help(overdue ? "Target date passed with issues still open" : "Linear target date")
            .transition(.opacity)
        } else if project.linear == nil || loaded {
            dash("No target date")
        } else {
            Skeleton(width: 44, height: 12)
        }
    }

    @ViewBuilder private var health: some View {
        if entry.status == .loading {
            HStack(spacing: 6) { Skeleton(width: 12, height: 12, radius: 6); Skeleton(width: 56, height: 12) }
        } else {
            HealthMark(status: entry.status).transition(.opacity)
        }
    }

    /// Missing or not applicable: a quiet dash, never a zero.
    private func dash(_ help: String) -> some View {
        Text(verbatim: "—").font(.system(size: 13)).foregroundStyle(Soot.muted).help(help)
    }

    /// A tool to connect is a quiet chip; a tool that failed says so in a word, the negative
    /// colour on the glyph only.
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
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .modifier(FocusOutline(radius: 14))
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
