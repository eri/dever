import SwiftUI

/// Home screen. Its one question: which project needs me now?
/// The KPI strip is also the list's filter; the list is sorted by urgency.
struct OverviewView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    let open: (Project) -> Void
    let newProject: () -> Void
    let importFrom: (ImportSheet.Source) -> Void

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All projects", attention = "Needs attention", incomplete = "Incomplete", onTrack = "On track"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var search = ""

    private var statuses: [(Project, ProjectStatus)] {
        app.projects.map { ($0, $0.status(store.snapshots[$0.id])) }
    }

    private func matches(_ filter: Filter, _ p: Project, _ s: ProjectStatus) -> Bool {
        switch filter {
        case .all: true
        case .attention: s == .needsAttention || s == .quiet
        case .incomplete: !p.isComplete
        case .onTrack: s == .onTrack
        }
    }

    private var rows: [(Project, ProjectStatus)] {
        statuses
            .filter { matches(filter, $0.0, $0.1) }
            .filter { search.isEmpty || $0.0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if app.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.gap) {
                        titleRow
                        kpiTabs
                        projectList
                    }
                    .padding(Theme.pad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .searchable(text: $search, placement: .toolbar, prompt: "Search projects")
            }
        }
        .sheetBackground()
        .navigationTitle("Overview")
        .windowTitleHidden()
        .task { if store.isStale { await store.refresh(app) } }
    }

    // MARK: Title row

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Overview").font(Theme.title).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(finding).font(Theme.body).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            freshness
            Button("New project", action: newProject).buttonStyle(PrimaryButtonStyle())
        }
    }

    /// The fact that most needs attention, stated first.
    private var finding: String {
        let attention = statuses.filter { matches(.attention, $0.0, $0.1) }.map(\.0)
        guard let lead = attention.max(by: { a, b in
            (store.snapshots[a.id]?.github?.mergedButOpen.count ?? 0) < (store.snapshots[b.id]?.github?.mergedButOpen.count ?? 0)
        }) else {
            return store.snapshots.isEmpty ? "Loading your projects…" : "Every project is on track."
        }
        let reason = lead.signals(store.snapshots[lead.id]).first
            .map { ": " + $0.prefix(1).lowercased() + $0.dropFirst() } ?? ""
        if attention.count == 1 {
            return "\(lead.name) needs attention\(reason)."
        }
        return "\(attention.count) of \(app.projects.count) projects need attention. \(lead.name)\(reason)."
    }

    private var freshness: some View {
        HStack(spacing: 6) {
            if store.isRefreshing {
                ProgressView().controlSize(.small).accessibilityLabel("Refreshing")
            } else if let last = store.lastRefresh {
                Text("Updated \(last.formatted(.relative(presentation: .named)))")
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
            Button { Task { await store.refresh(app) } } label: {
                Image(systemName: "arrow.clockwise").foregroundStyle(Theme.muted)
            }
            .buttonStyle(.borderless)
            .help("Refresh all projects")
            .accessibilityLabel("Refresh all projects")
            .keyboardShortcut("r")
            .disabled(store.isRefreshing)
        }
    }

    // MARK: KPI strip, doubling as the filter

    private var kpiTabs: some View {
        HStack(spacing: 0) {
            ForEach(Filter.allCases) { f in
                if f != Filter.allCases.first {
                    Rectangle().fill(Theme.border).frame(width: 1).padding(.vertical, 14)
                }
                kpiCell(f)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.border))
    }

    private func kpiCell(_ f: Filter) -> some View {
        let count = statuses.filter { matches(f, $0.0, $0.1) }.count
        let selected = filter == f
        let valueColor: Color = f == .attention && count > 0 ? Theme.negative : Theme.text
        return Button { filter = f } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(f.rawValue).font(Theme.smallStrong).foregroundStyle(selected ? Theme.text : Theme.muted)
                Text(count, format: .number).font(Theme.kpi).foregroundStyle(valueColor).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(selected ? Theme.text : Color.clear).frame(height: 2).padding(.horizontal, 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.rawValue): \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Project list

    private var projectList: some View {
        VStack(spacing: 0) {
            ProjectListHeader()
            ForEach(rows, id: \.0.id) { project, status in
                Rectangle().fill(Theme.rule).frame(height: 1)
                Button { open(project) } label: {
                    ProjectRow(project: project, status: status, snapshot: store.snapshots[project.id])
                }
                .buttonStyle(.plain)
                .hoverRow()
            }
            if rows.isEmpty {
                Rectangle().fill(Theme.rule).frame(height: 1)
                filteredEmpty
            }
        }
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var filteredEmpty: some View {
        HStack(spacing: 8) {
            Text(search.isEmpty ? "No project in \u{201C}\(filter.rawValue)\u{201D}."
                                : "No project matches \u{201C}\(search)\u{201D}.")
                .foregroundStyle(Theme.muted)
            Button("Show all projects") { filter = .all; search = "" }.buttonStyle(.link)
            Spacer()
        }
        .font(Theme.body)
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No projects yet", systemImage: "square.stack")
        } description: {
            Text("A project joins a Slack channel, a Linear project and, if you like, a GitHub repository.")
        } actions: {
            Button("New project", action: newProject).buttonStyle(PrimaryButtonStyle())
            HStack(spacing: 16) {
                Button("Import from Slack…") { importFrom(.slack) }.disabled(app.slack == nil)
                Button("Import from Linear…") { importFrom(.linear) }.disabled(app.linear == nil)
            }
            .buttonStyle(.link)
            if app.slack == nil || app.linear == nil {
                Text("Connect Slack and Linear in Accounts to import.").font(Theme.small).foregroundStyle(Theme.muted)
            }
        }
    }
}

// MARK: - Columns

/// Column widths shared by the header and the rows, so every figure lines up.
private enum Column {
    static let project: CGFloat = 240
    static let pulls: CGFloat = 96
    static let pipeline: CGFloat = 104
    static let slack: CGFloat = 132
    static let spacing: CGFloat = 24
}

private struct ProjectListHeader: View {
    var body: some View {
        HStack(spacing: Column.spacing) {
            Text("Project").frame(width: Column.project, alignment: .leading)
            Text("Delivery").frame(maxWidth: .infinity, alignment: .leading)
            Text("Pull requests").frame(width: Column.pulls, alignment: .trailing)
            Text("Pipeline").frame(width: Column.pipeline, alignment: .leading)
            Text("Slack this week").frame(width: Column.slack, alignment: .trailing)
        }
        .font(Theme.small)
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 20)
        .frame(height: 40)
    }
}

private struct ProjectRow: View {
    let project: Project
    let status: ProjectStatus
    let snapshot: ProjectSnapshot?

    var body: some View {
        HStack(alignment: .center, spacing: Column.spacing) {
            identity.frame(width: Column.project, alignment: .leading)
            delivery.frame(maxWidth: .infinity, alignment: .leading)
            pulls.frame(width: Column.pulls, alignment: .trailing)
            pipeline.frame(width: Column.pipeline, alignment: .leading)
            slack.frame(width: Column.slack, alignment: .trailing)
        }
        .font(Theme.body)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the project")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(project.name).font(Theme.bodyStrong).foregroundStyle(Theme.text).lineLimit(1)
                    .help(project.name)
                StatusBadge(status: status)
            }
            Text(links).font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1).help(links)
        }
    }

    private var links: String {
        let slack = project.slack.map { "#\($0.name)" } ?? "No Slack channel"
        let linear = project.linear?.name ?? "No Linear project"
        return "\(slack) · \(linear)"
    }

    @ViewBuilder
    private var delivery: some View {
        if let d = snapshot?.delivery {
            VStack(alignment: .leading, spacing: 6) {
                DeliveryStrip(delivery: d)
                deliveryCaption(d)
            }
        } else if project.linear == nil {
            Text("Link a Linear project to see delivery").font(Theme.small).foregroundStyle(Theme.muted)
        } else if let e = snapshot?.errors[.linear] {
            Text("Linear unavailable").font(Theme.small).foregroundStyle(Theme.negative).help(e)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.raised).frame(height: 8)
                RoundedRectangle(cornerRadius: 2).fill(Theme.raised).frame(width: 120, height: 12)
            }
            .accessibilityLabel("Loading")
        }
    }

    private func deliveryCaption(_ d: Delivery) -> some View {
        HStack(spacing: 4) {
            Text("\(d.shipped)/\(d.total) shipped")
                .foregroundStyle(Theme.text).monospacedDigit()
            if d.merged > 0 {
                Text("· \(d.merged) to close").foregroundStyle(Theme.chart3).monospacedDigit()
                    .help("Merged in GitHub but still open in Linear")
            } else if let target = snapshot?.linear?.targetDate {
                Text("· due \(target.formatted(.dateTime.day().month(.abbreviated)))").foregroundStyle(Theme.muted)
            }
        }
        .font(Theme.small)
        .lineLimit(1)
    }

    @ViewBuilder
    private var pulls: some View {
        if let g = snapshot?.github {
            VStack(alignment: .trailing, spacing: 2) {
                Text(g.openPRs, format: .number).foregroundStyle(Theme.text).monospacedDigit()
                Text("open").font(Theme.small).foregroundStyle(Theme.muted)
            }
        } else {
            dash(project.githubRepo == nil ? "No repository linked" : nil)
        }
    }

    @ViewBuilder
    private var pipeline: some View {
        if let g = snapshot?.github {
            PipelineBadge(state: g.pipeline)
        } else {
            dash(project.githubRepo == nil ? "No repository linked" : nil)
        }
    }

    @ViewBuilder
    private var slack: some View {
        if let s = snapshot?.slack {
            VStack(alignment: .trailing, spacing: 2) {
                Text(s.messagesThisWeek, format: .number).foregroundStyle(Theme.text).monospacedDigit()
                Text(s.lastActivity.map { "last \($0.formatted(.relative(presentation: .named)))" } ?? "no messages")
                    .font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1)
            }
        } else {
            dash(project.slack == nil ? "No Slack channel linked" : nil)
        }
    }

    /// Missing or not applicable: a grey dash, never a zero.
    private func dash(_ help: String?) -> some View {
        Text("—").foregroundStyle(Theme.muted).help(help ?? "Loading")
    }
}
