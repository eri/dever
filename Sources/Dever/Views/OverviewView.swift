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

    private var rows: [(Project, ProjectStatus)] {
        app.projects
            .map { ($0, $0.status(store.snapshots[$0.id])) }
            .filter { p, status in
                switch filter {
                case .all: true
                case .attention: status == .needsAttention || status == .quiet
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
                    VStack(alignment: .leading, spacing: 20) {
                        metrics
                        Picker("", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                            ForEach(rows, id: \.0.id) { project, status in
                                ProjectCard(project: project, status: status, snapshot: store.snapshots[project.id])
                                    .onTapGesture { open(project) }
                            }
                        }
                        if rows.isEmpty {
                            Text("No project matches this filter.").foregroundStyle(.secondary)
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
            MetricTile(value: app.projects.count, label: "Projects", tint: .accentColor)
            MetricTile(value: count { _, s in s == .onTrack }, label: "On track", tint: .green)
            MetricTile(value: count { _, s in s == .needsAttention || s == .quiet }, label: "Need attention", tint: .orange)
            MetricTile(value: count { p, _ in !p.isComplete }, label: "Incomplete", tint: .secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No projects yet", systemImage: "square.grid.2x2")
        } description: {
            Text("A Dever project links a Slack channel and a Linear project. Create one, or import existing ones.")
        } actions: {
            Button("New project…", action: newProject).buttonStyle(.borderedProminent)
            HStack {
                Button("Import from Slack…") { importFrom(.slack) }.disabled(app.slack == nil)
                Button("Import from Linear…") { importFrom(.linear) }.disabled(app.linear == nil)
            }
        }
    }
}

private struct MetricTile: View {
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StatusPill: View {
    let status: ProjectStatus

    var color: Color {
        switch status {
        case .needsAttention: .red
        case .incomplete: .orange
        case .quiet: .yellow
        case .onTrack: .green
        case .loading: .secondary
        }
    }

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

private struct ProjectCard: View {
    let project: Project
    let status: ProjectStatus
    let snapshot: ProjectSnapshot?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name).font(.headline).lineLimit(1)
                Spacer()
                StatusPill(status: status)
            }
            linksRow
            Divider()
            linearSection
            slackRow
            if project.githubRepo != nil { githubRow }
            let signals = project.signals(snapshot)
            if !signals.isEmpty {
                Label(signals.joined(separator: " · "), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hovering ? Color.accentColor : Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(hovering ? 0.12 : 0.04), radius: hovering ? 8 : 3, y: 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var linksRow: some View {
        HStack(spacing: 10) {
            linkBadge(ServiceKind.slack.symbol, project.slack.map { "#\($0.name)" })
            linkBadge(ServiceKind.linear.symbol, project.linear?.name)
            if let repo = project.githubRepo {
                linkBadge(ServiceKind.github.symbol, repo.split(separator: "/").last.map(String.init))
            }
        }
        .font(.caption)
    }

    private func linkBadge(_ symbol: String, _ text: String?) -> some View {
        Label(text ?? "not linked", systemImage: symbol)
            .lineLimit(1)
            .foregroundStyle(text == nil ? Color.orange : Color.secondary)
    }

    @ViewBuilder
    private var linearSection: some View {
        if let l = snapshot?.linear {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(Int((l.progress * 100).rounded()))%").font(.subheadline.weight(.semibold))
                    Text("\(l.done)/\(l.total) issues done").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let target = l.targetDate {
                        Label(target.formatted(.dateTime.day().month(.abbreviated)), systemImage: "flag")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: l.progress).tint(l.progress >= 1 ? .green : .accentColor)
                Text("\(l.inProgress) in progress · \(l.todo) to do" + (l.lead.map { " · Lead: \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } else if project.linear == nil {
            Text("Link a Linear project to track progress.").font(.caption).foregroundStyle(.secondary)
        } else if snapshot == nil {
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private var slackRow: some View {
        if let s = snapshot?.slack {
            row(ServiceKind.slack.symbol) {
                Text("\(s.messagesThisWeek) messages this week")
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
                pipelineBadge(g.pipeline)
                if let branch = g.lastRun?.head_branch { Text(branch).foregroundStyle(.secondary).lineLimit(1) }
                Text("· \(g.openPRs) open PR\(g.openPRs == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
        }
    }

    private func pipelineBadge(_ state: ProjectSnapshot.PipelineState) -> some View {
        let (text, color, symbol): (String, Color, String) = switch state {
        case .passing: ("Passing", .green, "checkmark.circle.fill")
        case .failing: ("Failing", .red, "xmark.circle.fill")
        case .running: ("Running", .orange, "clock.fill")
        case .unknown: ("No runs", .secondary, "minus.circle")
        }
        return Label(text, systemImage: symbol).foregroundStyle(color)
    }

    private func row<C: View>(_ symbol: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).frame(width: 16).foregroundStyle(.secondary)
            content()
        }
        .font(.caption)
    }
}
