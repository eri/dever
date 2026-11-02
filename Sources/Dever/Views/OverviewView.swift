import SwiftUI

/// Home screen: every project as a card with its Linear progress, Slack activity and pipeline.
struct OverviewView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    let open: (Project) -> Void
    let newProject: () -> Void
    let importFrom: (ImportSheet.Source) -> Void

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", attention = "Needs attention", incomplete = "Incomplete"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var search = ""

    private func needsAttention(_ status: ProjectStatus) -> Bool {
        status == .needsAttention || status == .quiet
    }

    private var rows: [(Project, ProjectStatus)] {
        app.projects
            .map { ($0, $0.status(store.snapshots[$0.id])) }
            .filter { p, status in
                switch filter {
                case .all: true
                case .attention: needsAttention(status)
                case .incomplete: !p.isComplete
                }
            }
            .filter { search.isEmpty || $0.0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
    }

    private func count(_ match: (Project, ProjectStatus) -> Bool) -> Int {
        app.projects.filter { match($0, $0.status(store.snapshots[$0.id])) }.count
    }

    var body: some View {
        Group {
            if app.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        metrics
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Filter", selection: $filter) {
                                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            if rows.isEmpty {
                                filteredEmptyState
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 16, alignment: .top)], spacing: 16) {
                                    ForEach(rows, id: \.0.id) { project, status in
                                        Button { open(project) } label: {
                                            ProjectCard(project: project, status: status, snapshot: store.snapshots[project.id])
                                        }
                                        .buttonStyle(PressableStyle())
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .searchable(text: $search, placement: .toolbar, prompt: "Search projects")
            }
        }
        .navigationTitle("Overview")
        .navigationSubtitle(subtitle)
        .toolbar {
            Button { Task { await store.refresh(app) } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh all projects")
            .keyboardShortcut("r")
            .disabled(store.isRefreshing)
        }
        .task {
            // Refresh on appear when stale, then every few minutes while the overview is visible.
            while !Task.isCancelled {
                if store.isStale { await store.refresh(app) }
                try? await Task.sleep(nanoseconds: UInt64(OverviewStore.staleAfter * 1_000_000_000))
            }
        }
    }

    private var subtitle: String {
        if store.isRefreshing { return "Refreshing…" }
        guard let last = store.lastRefresh else { return "" }
        return "Updated \(last.formatted(.relative(presentation: .named)))"
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            MetricTile(value: app.projects.count, label: "Projects", symbol: "square.grid.2x2", tint: .accentColor)
            MetricTile(value: count { _, s in s == .onTrack }, label: "On track",
                       symbol: ProjectStatus.onTrack.symbol, tint: ProjectStatus.onTrack.tint)
            MetricTile(value: count { _, s in needsAttention(s) }, label: "Needs attention",
                       symbol: ProjectStatus.needsAttention.symbol, tint: ProjectStatus.needsAttention.tint)
            MetricTile(value: count { p, _ in !p.isComplete }, label: "Incomplete",
                       symbol: ProjectStatus.incomplete.symbol, tint: ProjectStatus.incomplete.tint)
        }
    }

    private var filteredEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            EmptySection(
                title: search.isEmpty ? "No projects in \u{201C}\(filter.rawValue)\u{201D}" : "No projects match \u{201C}\(search)\u{201D}",
                message: filter == .attention ? "Every tracked project is on track." : "Try another filter or search."
            )
            Button("Show all projects") { filter = .all; search = "" }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No projects yet", systemImage: "square.grid.2x2")
        } description: {
            Text("A project links a Slack channel to a Linear project, so you can follow both in one place.")
        } actions: {
            Button("Create project…", action: newProject).buttonStyle(.borderedProminent)
            HStack {
                Button("Import from Slack…") { importFrom(.slack) }.disabled(app.slack == nil)
                Button("Import from Linear…") { importFrom(.linear) }.disabled(app.linear == nil)
            }
            if app.slack == nil || app.linear == nil {
                Text("Connect Slack and Linear in Accounts to import.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct MetricTile: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint).font(.callout)
            Text(value, format: .number)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surface()
        .accessibilityElement(children: .combine)
    }
}

private struct ProjectCard: View {
    let project: Project
    let status: ProjectStatus
    let snapshot: ProjectSnapshot?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(project.name).font(.headline).lineLimit(1).help(project.name)
                    Spacer(minLength: 8)
                    StatusBadge(status: status)
                }
                linksRow
            }
            linearSection
            VStack(alignment: .leading, spacing: 6) {
                slackRow
                if project.githubRepo != nil { githubRow }
            }
            let signals = project.signals(snapshot)
            if !signals.isEmpty {
                Label {
                    Text(signals.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.caption)
                .help(signals.joined(separator: "\n"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .surface(highlighted: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the project")
    }

    private var linksRow: some View {
        HStack(spacing: 12) {
            linkBadge(.slack, project.slack.map { "#\($0.name)" })
            linkBadge(.linear, project.linear?.name)
            if let repo = project.githubRepo {
                linkBadge(.github, repo.split(separator: "/").last.map(String.init))
            }
        }
        .font(.caption)
    }

    private func linkBadge(_ service: ServiceKind, _ text: String?) -> some View {
        Label(text ?? "No \(service.label)", systemImage: text == nil ? "circle.dashed" : service.symbol)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .help(text ?? "No \(service.label) linked")
    }

    @ViewBuilder
    private var linearSection: some View {
        if let l = snapshot?.linear {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(l.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    Text("\(l.done) of ^[\(l.total) issue](inflect: true) done")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    if let target = l.targetDate {
                        Label(target.formatted(.dateTime.day().month(.abbreviated)), systemImage: "flag")
                            .font(.caption).foregroundStyle(.secondary)
                            .help("Target date")
                    }
                }
                ProgressView(value: l.progress)
                    .tint(l.progress >= 1 ? .green : .accentColor)
                    .accessibilityLabel("Progress")
                Text("\(l.inProgress) in progress · \(l.todo) to do" + (l.lead.map { " · Lead: \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
            }
        } else if project.linear == nil {
            EmptySection(title: "No Linear project", message: "Link one to track progress.")
        } else if snapshot == nil {
            ProgressView().controlSize(.small).accessibilityLabel("Loading")
        }
    }

    @ViewBuilder
    private var slackRow: some View {
        if let s = snapshot?.slack {
            row(ServiceKind.slack.symbol) {
                Text("^[\(s.messagesThisWeek) message](inflect: true) this week").monospacedDigit()
                if let last = s.lastActivity {
                    Text("· last \(last.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var githubRow: some View {
        if let g = snapshot?.github {
            row(ServiceKind.github.symbol) {
                PipelineBadge(state: g.pipeline)
                if let branch = g.lastRun?.head_branch {
                    Text(branch).foregroundStyle(.secondary).lineLimit(1).help(branch)
                }
                Text("· ^[\(g.openPRs) open pull request](inflect: true)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func row<C: View>(_ symbol: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).frame(width: 16).foregroundStyle(.secondary).accessibilityHidden(true)
            content()
        }
        .font(.caption)
    }
}
