import SwiftUI

/// One project. Its question: what is left to ship, and what needs closing?
struct ProjectDetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    let project: Project
    let edit: () -> Void

    @ObservedObject private var issueStore = IssueStore.shared
    @State private var messages: [SlackMessage] = []
    @State private var users: [String: SlackUser] = [:]
    @State private var shownMessages = 8
    @State private var hasEarlier = false
    @State private var loadingEarlier = false
    @State private var slackExpanded = false
    @State private var slackFocus: String?
    @State private var customEmoji: [String: URL] = [:]
    @State private var previewFile: SlackFile?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulls: [ProjectPullRequests.Match] = []
    @State private var pullsScoped = false
    @State private var runs: [GitHubRun] = []
    @State private var merged: [MergedPull] = []
    /// Why a panel has nothing: not connected, token rejected, offline, or a failure.
    @State private var states: [ServiceKind: ServiceState] = [:]
    /// When each service last loaded on this page, for the failure rows.
    @State private var lastLoaded: [ServiceKind: Date] = [:]
    @StateObject private var flow = ConnectFlow()
    @State private var loading = false
    @State private var loaded = false
    @State private var expanded: Set<String> = []
    @State private var workFilter: WorkFilter = .all

    private var status: ProjectStatus { project.status(store.snapshots[project.id]) }

    /// The linked tools with no token: one missing gets its invitation inside its panel,
    /// several get one section at the top and quiet placeholders in the panels.
    private var missing: [ServiceKind] { app.missingServices(for: project) }
    private var linkedServices: [ServiceKind] {
        [project.slack != nil ? .slack : nil, project.linear != nil ? .linear : nil, project.githubRepo != nil ? .github : nil]
            .compactMap { $0 }
    }
    /// Reloads when a token arrives, so a panel fills in without leaving the page.
    private var connectionKey: String { "\(app.slack != nil)-\(app.linear != nil)-\(app.github != nil)" }

    private var issues: [LinearIssue] { project.linear.map { issueStore.issues(project: $0.id) } ?? [] }

    private var delivery: Delivery {
        Delivery(issues: issues.map { ($0.identifier, $0.state.type, $0.state.name) },
                 openPR: Set(pulls.compactMap(\.issue)),
                 mergedPR: Set(merged.compactMap(\.issue)))
    }

    var body: some View {
        GeometryReader { geo in
            // The same two columns as the skeleton, loaded or not: the work on the left,
            // the conversation alongside it. Below ~1000px they stack.
            let twoColumns = geo.size.width >= 1000
            // In the wide view the page stops scrolling: the messages scroll inside their
            // panel and the thread pane stays put beside them. Same ScrollView either way,
            // so the panel's state (open thread, draft) survives the switch.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 24) {
                    titleRow
                    if missing.count > 1 {
                        ConnectSection(project: project, services: linkedServices, flow: flow)
                    }
                    // The Slack panel keeps one place in the hierarchy whichever layout is on,
                    // so open threads and a half-written reply survive a switch to the wide view.
                    if twoColumns {
                        HStack(alignment: .top, spacing: 16) {
                            if !slackExpanded { workColumn.frame(maxWidth: .infinity) }
                            slackPanel
                                .frame(width: slackExpanded ? nil : min(420, geo.size.width * 0.34))
                                .frame(maxHeight: slackExpanded ? .infinity : nil, alignment: .top)
                        }
                    } else {
                        VStack(spacing: 16) {
                            if !slackExpanded { workColumn }
                            slackPanel.frame(maxHeight: slackExpanded ? .infinity : nil, alignment: .top)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(width: geo.size.width, height: slackExpanded ? geo.size.height : nil, alignment: .topLeading)
            }
            .scrollDisabled(slackExpanded)
        }
        .background(Soot.ground)
        .modifier(FilePreviewHost(preview: $previewFile))
        .navigationTitle(project.name)
        .windowTitleHidden()
        .task { await load() }
        .sheet(isPresented: $flow.githubSheet) { GitHubLoginSheet() }
        .onChange(of: connectionKey) { _, _ in Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSlackWide)) { _ in
            slackExpanded.toggle()
            if slackExpanded { shownMessages = max(shownMessages, 30) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFirstIssue)) { _ in
            if let first = workList.first?.issue {
                NotificationCenter.default.post(name: .openIssue, object: IssueRoute(project: project, issue: first))
            }
        }
    }

    private var workColumn: some View {
        workPanel
    }

    // MARK: Title row

    /// The page's toolbar: name and status, the linked tools as chips, and on the right the
    /// two actions on the project itself. Its height does not depend on what has loaded.
    private var titleRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(project.name).font(.system(size: 32, weight: .semibold)).tracking(-0.8)
                        .foregroundStyle(Soot.ink)
                        .lineLimit(1)
                        .help(project.name)
                        .accessibilityAddTraits(.isHeader)
                    if status == .loading { Skeleton(width: 72, height: 20, radius: 4) } else { StatusBadge(status: status) }
                }
                linkRow
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Button { Task { await load(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ToolbarButton(busy: loading))
                .disabled(loading)
                .help("Refresh this project (⌘R)")
                .accessibilityLabel("Refresh this project")
                .accessibilityValue(loading ? "Refreshing" : "")
                .keyboardShortcut("r")
                Button(action: edit) {
                    Label("Edit project", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(ToolbarButton())
                .help("Change the name and linked tools (⌘E)")
                .accessibilityLabel("Edit project")
                .keyboardShortcut("e")
            }
            .fixedSize()
            .padding(.top, 4)
        }
    }

    private var slackURL: URL? {
        guard let channel = project.slack, let slack = app.slack else { return nil }
        return URL(string: "https://\(slack.domain).slack.com/archives/\(channel.id)")
    }

    /// The linked tools, each a chip that opens it. A tool linked but not reachable (no
    /// Slack domain yet) keeps its chip, so the row reads the same in every state.
    private var linkRow: some View {
        HStack(spacing: 4) {
            if let channel = project.slack {
                ToolChip(service: .slack, text: "#\(channel.name)", url: slackURL)
            }
            if let linear = project.linear {
                ToolChip(service: .linear, text: linear.name, url: URL(string: linear.url))
            }
            if let repo = project.githubRepo {
                ToolChip(service: .github, text: repo, url: URL(string: "https://github.com/\(repo)"))
            }
            if !project.isComplete {
                Button(action: edit) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text("Link a tool")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Soot.lime)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .contentShape(Capsule())
                    .modifier(FocusOutline(radius: 14))
                }
                .buttonStyle(.plain)
                .help("Link a Slack channel, a Linear project or a GitHub repository")
            }
        }
        .padding(.leading, -8)
        .frame(height: 28)
    }

    // MARK: Work (the signature block)

    private var linearURL: URL? { project.linear.flatMap { URL(string: $0.url) } }
    private var repoURL: URL? { project.githubRepo.flatMap { URL(string: "https://github.com/\($0)") } }

    /// The list's filter: every issue, or one delivery stage.
    private enum WorkFilter: Hashable { case all, stage(Delivery.Stage) }

    /// An issue with its stage and the pull requests matched to it: one row of the list.
    private struct WorkItem: Identifiable {
        var issue: LinearIssue
        var stage: Delivery.Stage
        var merged: [MergedPull]
        var open: [ProjectPullRequests.Match]
        var id: String { issue.id }
    }

    private var workItems: [WorkItem] {
        let openByIssue = Dictionary(grouping: pulls.filter { $0.issue != nil }, by: { $0.issue! })
        let mergedByIssue = Dictionary(grouping: merged.filter { $0.issue != nil }, by: { $0.issue! })
        return issues.compactMap { issue in
            let open = openByIssue[issue.identifier] ?? []
            let merged = mergedByIssue[issue.identifier] ?? []
            guard let stage = Delivery.stage(stateType: issue.state.type, stateName: issue.state.name,
                                             openPR: !open.isEmpty, mergedPR: !merged.isEmpty) else { return nil }
            return WorkItem(issue: issue, stage: stage, merged: merged, open: open)
        }
    }

    /// The chosen filter, or everything when its stage has emptied.
    private var currentFilter: WorkFilter {
        if case .stage(let s) = workFilter, delivery.count(s) == 0 { return .all }
        return workFilter
    }

    /// Under "All", what needs a hand comes first (merged but not moved, then in review…)
    /// and what is done last; within a stage, Linear's own order.
    private var workList: [WorkItem] {
        let items = workItems
        switch currentFilter {
        case .all: return Delivery.Stage.attentionOrder.flatMap { stage in items.filter { $0.stage == stage } }
        case .stage(let stage): return items.filter { $0.stage == stage }
        }
    }

    private var workTabs: [(label: String, count: Int, tab: WorkFilter)] {
        [("All", delivery.total, WorkFilter.all)]
            + Delivery.Stage.allCases.map { ($0.label, delivery.count($0), WorkFilter.stage($0)) }.filter { $0.1 > 0 }
    }

    /// Pull requests of the repository that no issue of the project cites (whole-repository
    /// projects, or a project with no Linear): they keep their own list under the issues.
    private var unlinkedOpen: [ProjectPullRequests.Match] { pulls.filter { $0.issue == nil } }
    private var unlinkedMerged: [MergedPull] { merged.filter { $0.issue == nil } }

    /// The latest run of each branch, newest first in `runs`.
    private var runByBranch: [String: GitHubRun] {
        var out: [String: GitHubRun] = [:]
        for run in runs { if let b = run.head_branch, out[b] == nil { out[b] = run } }
        return out
    }

    private func pipeline(of pull: GitHubPull) -> ProjectSnapshot.PipelineState? {
        runByBranch[pull.head.ref].map(ProjectSnapshot.PipelineState.init(run:))
    }

    /// One line for the open pull requests' pipelines: failing wins, then running, then passing.
    private var pipelineSummary: (state: ProjectSnapshot.PipelineState, text: String)? {
        let states = pulls.compactMap { pipeline(of: $0.pull) }
        let failing = states.filter { $0 == .failing }.count
        if failing > 0 { return (.failing, failing == 1 ? "1 pipeline failing" : "\(failing) pipelines failing") }
        if states.contains(.running) { return (.running, "Pipeline running") }
        if states.contains(.passing) { return (.passing, "Pipelines passing") }
        return nil
    }

    private var githubReady: Bool { project.githubRepo != nil && states[.github] == nil && loaded }

    private var workPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(title: project.linear == nil ? "Pull requests" : "Delivery",
                        subtitle: project.linear == nil ? project.githubRepo : "Issues joined with their pull requests")
            if project.linear == nil && project.githubRepo == nil {
                QuietEmpty(symbol: "link", text: "Link a Linear project or a GitHub repository to see the work here")
            } else if !loaded, states[.linear] == nil, states[.github] == nil {
                workSkeleton
            } else {
                if project.linear != nil { linearPart }
                if project.githubRepo != nil { githubPart }
            }
        }
        .sootPanel()
    }

    /// Headline, bar, the stages as the filter, then the issues.
    @ViewBuilder
    private var linearPart: some View {
        if states[.linear] == .notConnected {
            if missing.count > 1 {
                ConnectPlaceholder(service: .linear, widths: [90, 320, 220, 280])
            } else {
                ConnectPanelBody(service: .linear, project: project, flow: flow)
            }
        } else if let state = states[.linear] {
            failure(.linear, state)
        } else if delivery.total == 0 {
            QuietEmpty(symbol: "tray", text: "No issues in this project yet")
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(Double(delivery.shipped) / Double(delivery.total), format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 34, weight: .semibold)).tracking(-1).foregroundStyle(Soot.ink).monospacedDigit()
                Text("\(delivery.shipped) of \(delivery.total) shipped").font(.system(size: 14)).foregroundStyle(Soot.muted)
                    .monospacedDigit()
                Spacer(minLength: 16)
                if let summary = pipelineSummary, let repo = project.githubRepo,
                   let url = URL(string: "https://github.com/\(repo)/actions") {
                    HoverLink(destination: url) {
                        HStack(spacing: 5) {
                            PipelineGlyph(state: summary.state)
                            Text(summary.text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                        }
                    }
                    .help("Open the repository's workflow runs")
                    .accessibilityLabel("\(summary.text). Opens the workflow runs on GitHub")
                }
            }
            deliveryBar
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) { stageTabs; Spacer(minLength: 0); updateInLinear }
                VStack(alignment: .leading, spacing: 10) { stageTabs; updateInLinear }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(capped(workList, key: "work")) { item in workRow(item) }
                showAll(workList.count, key: "work")
                if githubReady, pulls.isEmpty, merged.isEmpty {
                    QuietEmpty(symbol: "arrow.triangle.pull", text: "No pull request cites one of these issues yet")
                }
            }
        }
    }

    private var stageTabs: some View {
        CountTabs(tabs: workTabs, selection: Binding(get: { currentFilter }, set: { workFilter = $0 })) { filter in
            if case .stage(let s) = filter { DeliveryStrip.color(s) } else { nil }
        }
    }

    /// The action on the merged-but-not-moved issues, shown while they are in the list.
    @ViewBuilder
    private var updateInLinear: some View {
        let behind = delivery.count(.merged)
        if behind > 0, let url = linearURL, currentFilter == .all || currentFilter == .stage(.merged) {
            HoverLink(destination: url) {
                HStack(spacing: 4) { Text("Update \(behind) in Linear"); Image(systemName: "arrow.up.right") }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Soot.lime)
            }
            .help("Open the project in Linear to move the merged issues forward")
            .accessibilityLabel("Update \(behind) merged issues in Linear")
        }
    }

    /// Rounded segments with gaps, one per stage, proportional to its issues. The stages
    /// not selected step back.
    private var deliveryBar: some View {
        GeometryReader { geo in
            let stages = Delivery.Stage.allCases.filter { delivery.count($0) > 0 }
            let gap: CGFloat = 4
            let usable = geo.size.width - gap * CGFloat(max(stages.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(stages, id: \.self) { stage in
                    Capsule().fill(DeliveryStrip.color(stage))
                        .frame(width: max(10, usable * CGFloat(delivery.count(stage)) / CGFloat(max(delivery.total, 1))))
                        .opacity(currentFilter == .all || currentFilter == .stage(stage) ? 1 : 0.3)
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    /// One issue: priority, key, title, then its pull requests, due date and assignee. The row
    /// opens the issue; each pull request chip opens the PR on GitHub.
    private func workRow(_ item: WorkItem) -> some View {
        let issue = item.issue
        let chips = HStack(spacing: 6) {
            ForEach(item.open.prefix(2)) { m in
                PullChip(number: m.pull.number, kind: m.pull.draft == true ? .draft : .open,
                         pipeline: pipeline(of: m.pull), title: m.pull.title, url: URL(string: m.pull.html_url)!)
            }
            ForEach(item.merged.prefix(max(0, 2 - min(item.open.count, 2)))) { m in
                PullChip(number: m.number, kind: .merged, title: m.title, url: URL(string: m.url)!)
            }
            if item.open.count + item.merged.count > 2 {
                Text("+\(item.open.count + item.merged.count - 2)").font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted)
                    .monospacedDigit()
                    .accessibilityLabel("\(item.open.count + item.merged.count - 2) more pull requests")
            }
            if githubReady, item.stage == .building {
                Text("No PR yet").font(.system(size: 12)).foregroundStyle(Soot.muted)
            }
        }
        let meta = HStack(spacing: 12) {
            DueDateText(dueDate: issue.dueDate)
            if let person = issue.assignee {
                LinearAvatar(name: person.name, avatarURL: person.avatarUrl).help(person.name)
                    .accessibilityLabel("Assigned to \(person.name)")
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(Soot.muted)
                    .help("Unassigned").accessibilityLabel("Unassigned")
            }
        }
        let summary = [item.open.isEmpty ? nil : "\(item.open.count) open pull request\(item.open.count == 1 ? "" : "s")",
                       item.merged.isEmpty ? nil : "\(item.merged.count) merged"].compactMap { $0 }.joined(separator: ", ")
        return WorkTile(value: IssueRoute(project: project, issue: issue), trailing: { chips; meta }) {
            PriorityGlyph(priority: issue.priority, dimmed: issue.priority == nil || issue.priority == 0)
                .help(LinearPriority.label(issue.priority))
            IDPill(text: issue.identifier)
            Text(MarkdownTheme.inline(issue.title, size: 14)).font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1)
                .help(issue.title)
                .layoutPriority(1)
            Spacer(minLength: 12)
        }
        .accessibilityLabel("\(issue.identifier), \(issue.title). \(item.stage.label)\(summary.isEmpty ? "" : ", " + summary)")
        .accessibilityHint("Opens the issue")
    }

    /// Pull requests, with their states inside the panel: an invitation to connect, a failure,
    /// or the ones no issue cites.
    @ViewBuilder
    private var githubPart: some View {
        if states[.github] == .notConnected {
            if missing.count > 1 {
                ConnectPlaceholder(service: .github, widths: [300, 240, 280])
            } else {
                ConnectPanelBody(service: .github, project: project, flow: flow)
            }
        } else if let state = states[.github] {
            failure(.github, state, compact: project.linear != nil && states[.linear] != nil)
        } else if !unlinkedOpen.isEmpty || !unlinkedMerged.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if project.linear != nil {
                    Text(states[.linear] == nil ? "Pull requests without an issue" : "Pull requests")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                }
                let rows: [UnlinkedPull] = unlinkedOpen.map { .open($0) } + unlinkedMerged.map { .merged($0) }
                ForEach(capped(rows, key: "unlinked")) { row in
                    switch row {
                    case .open(let m):
                        pullRow(kind: m.pull.draft == true ? .draft : .open, pipeline: pipeline(of: m.pull), title: m.pull.title,
                                number: m.pull.number, url: m.pull.html_url, trailing: m.pull.user.login)
                    case .merged(let m):
                        pullRow(kind: .merged, pipeline: nil, title: m.title ?? "Pull request #\(m.number)", number: m.number,
                                url: m.url, trailing: m.mergedAt.map { $0.formatted(.relative(presentation: .named)) })
                    }
                }
                showAll(rows.count, key: "unlinked")
            }
        } else if project.linear == nil {
            QuietEmpty(symbol: "arrow.triangle.pull", text: "No pull requests")
        }
    }

    private enum UnlinkedPull: Identifiable {
        case open(ProjectPullRequests.Match), merged(MergedPull)
        var id: String {
            switch self {
            case .open(let m): "open-\(m.pull.number)"
            case .merged(let m): "merged-\(m.number)"
            }
        }
    }

    /// Two lines for a pull request on its own: what changed, then number and kind.
    private func pullRow(kind: PullChip.Kind, pipeline: ProjectSnapshot.PipelineState?, title: String, number: Int,
                         url: String, trailing: String?) -> some View {
        let parts = PullTitle.split(title)
        let (symbol, tint, word): (String, Color, String) = switch kind {
        case .merged: ("arrow.triangle.merge", Theme.chart1, "merged")
        case .open: ("arrow.triangle.pull", Theme.chart2, "open")
        case .draft: ("pencil.line", Soot.muted, "draft")
        }
        return TileRow(url: URL(string: url)) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint).frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(parts.title).font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1).help(title)
                HStack(spacing: 6) {
                    Text(verbatim: "#\(number)")
                    Text("·"); Text(word)
                    if let kind = parts.kind { Text("·"); Text(kind) }
                }
                .font(.system(size: 12)).foregroundStyle(Soot.muted)
            }
            Spacer(minLength: 12)
            if let pipeline { PipelineGlyph(state: pipeline) }
            if let trailing {
                Text(trailing).font(.system(size: 12)).foregroundStyle(Soot.muted).frame(minWidth: 70, alignment: .trailing)
            }
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens on GitHub")
    }

    /// Rows of the same shape as the list, while it loads.
    private var workSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            if project.linear != nil {
                HStack(alignment: .lastTextBaseline, spacing: 10) { Skeleton(width: 90, height: 34); Skeleton(width: 120) }
                Skeleton(height: 10, radius: 5)
                HStack(spacing: 6) { ForEach(0..<4, id: \.self) { _ in Skeleton(width: 96, height: 30, radius: 15) } }
            }
            VStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 12) {
                        Skeleton(width: 12, height: 12, radius: 2)
                        Skeleton(width: 64, height: 20, radius: 5)
                        Skeleton(width: [280, 220, 320, 250, 200][i], height: 12)
                        Spacer()
                        Skeleton(width: 66, height: 26, radius: 13)
                        Skeleton(width: 22, height: 22, radius: 11)
                    }
                    .padding(.horizontal, 12).frame(height: 46)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading the project's work")
    }

    // MARK: Slack

    private var slackPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if slackExpanded {
                    // The way back sits where a back control is looked for: leading, before the title.
                    Button { toggleSlackWide() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                            Text("Back")
                        }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(Soot.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Soot.edge))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .modifier(FocusOutline(radius: 15))
                    .help("Back to the project (⌘⇧E)")
                    .accessibilityLabel("Back to the project")
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    Rectangle().fill(Soot.line).frame(width: 1, height: 22)
                }
                BrandLogo(service: .slack, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.slack.map { "#\($0.name)" } ?? "Slack").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Soot.ink).accessibilityAddTraits(.isHeader)
                    Text(slackSubtitle).font(.system(size: 12)).foregroundStyle(Soot.muted)
                }
                Spacer()
                if slackExpanded, let url = slackURL {
                    Link(destination: url) { HStack(spacing: 4) { Text("Open in Slack"); Image(systemName: "arrow.up.right") } }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
                        .handCursor()
                        .help("Open the channel in Slack")
                }
                if project.slack != nil, !slackExpanded {
                    Button { toggleSlackWide() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Soot.ink).frame(width: 30, height: 30).background(Soot.ground, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .modifier(FocusOutline(radius: 15))
                    .help("Read the conversation full width (⌘⇧E)")
                    .accessibilityLabel("Read the conversation full width")
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                }
            }
            if project.slack == nil {
                EmptySection(title: "No Slack channel", message: "Link a channel to follow its conversation here.")
            } else if states[.slack] == .notConnected {
                if missing.count > 1 {
                    ConnectPlaceholder(service: .slack, widths: [120, 260, 96, 220])
                } else {
                    ConnectPanelBody(service: .slack, project: project, flow: flow)
                }
            } else if let state = states[.slack] {
                failure(.slack, state)
            } else if !loaded {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(0..<3, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            Skeleton(width: [120, 96, 140][i], height: 14)
                            Skeleton(height: 12)
                            Skeleton(width: [220, 160, 260][i], height: 12)
                        }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Loading messages")
            } else if messages.isEmpty {
                EmptySection(title: "No messages yet", message: "Messages posted in #\(project.slack?.name ?? "") appear here.")
            } else {
                SlackThreadView(messages: messages, users: users, domain: app.slack?.domain,
                                channelID: project.slack?.id, channelName: project.slack?.name,
                                shown: slackExpanded ? shownMessages : railPlan.count,
                                hasEarlier: hasEarlier, loadingEarlier: loadingEarlier,
                                wide: slackExpanded, focus: slackFocus, customEmoji: customEmoji,
                                showEarlier: { Task { await showEarlier() } },
                                openWide: slackExpanded ? nil : { m in
                                    slackFocus = m.ts
                                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                                        slackExpanded = true
                                        shownMessages = max(shownMessages, 30)
                                    }
                                    Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if slackFocus == m.ts { slackFocus = nil } }
                                },
                                expand: slackExpanded ? nil : { toggleSlackWide() },
                                actions: slackActions)
            }
        }
        .sootPanel()
    }

    // MARK: Capped lists

    private static let cap = 6

    private func capped<T>(_ list: [T], key: String) -> [T] {
        expanded.contains(key) ? list : Array(list.prefix(Self.cap))
    }

    @ViewBuilder
    private func showAll(_ count: Int, key: String) -> some View {
        if count > Self.cap {
            ShowAllButton(count: count, expanded: Binding(
                get: { expanded.contains(key) },
                set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } }))
        }
    }

    // MARK: Loading

    /// The failure row of a panel, with the time of the last good load when there was one.
    private func failure(_ service: ServiceKind, _ state: ServiceState, compact: Bool = false) -> some View {
        let snapshot = store.snapshots[project.id]
        let fromSnapshot: Date? = switch service {
        case .slack: snapshot?.slack != nil ? snapshot?.updatedAt : nil
        case .linear: snapshot?.linear != nil ? snapshot?.updatedAt : nil
        case .github: snapshot?.github != nil ? snapshot?.updatedAt : nil
        }
        return ServiceFailureRow(service: service, state: state, lastLoaded: lastLoaded[service] ?? fromSnapshot,
                                 retry: { Task { await load(force: true) } }, flow: flow, compact: compact)
    }

    private func load(force: Bool = false) async {
        loading = true
        defer { loading = false; loaded = true }
        states = [:]
        // A tool without a token is an invitation, not a call that fails.
        for service in missing { states[service] = .notConnected }
        async let s: Void = loadSlack()
        // GitHub needs the Linear issues to tell which pull requests belong to the project.
        await loadLinear(force: force)
        await loadGitHub()
        await s
    }

    private func loadLinear(force: Bool) async {
        guard let id = project.linear?.id, states[.linear] == nil else { return }
        do {
            _ = try await issueStore.load(project: id, force: force, app: app)
            lastLoaded[.linear] = Date()
        } catch { states[.linear] = app.failure(error, .linear) }
    }

    private func loadSlack() async {
        guard let id = project.slack?.id, states[.slack] == nil else { return }
        do {
            let page = try await app.withSlack { try await $0.historyPage(id, limit: 20) }
            merge(page.messages)
            lastLoaded[.slack] = Date()
            if messages.count <= 20 { hasEarlier = page.hasMore }
            if let team = app.slack?.teamID {
                // One users.list per quarter hour across the app, not one per visit.
                users = try await app.withSlack { try await SlackDirectory.shared.users(team: team, via: $0) }
            }
            let authors = Set(messages.prefix(shownMessages).compactMap(\.user)).compactMap { users[$0] }
            Task.detached(priority: .utility) { await SlackMediaCache.shared.prefetchAvatars(authors) }
            if customEmoji.isEmpty, let team = app.slack?.teamID {
                customEmoji = (try? await app.withSlack { await SlackDirectory.shared.customEmoji(team: team, via: $0) }) ?? [:]
            }
        } catch { states[.slack] = app.failure(error, .slack) }
    }

    /// New messages replace the ones with the same `ts`; the rest stays as loaded, so a
    /// refresh never throws away earlier pages or re-renders unchanged rows.
    private func merge(_ incoming: [SlackMessage]) {
        var byTS = Dictionary(messages.map { ($0.ts, $0) }, uniquingKeysWith: { _, new in new })
        for m in incoming where m.subtype != "channel_join" && m.subtype != "channel_leave" { byTS[m.ts] = m }
        messages = byTS.values.sorted { $0.ts > $1.ts }
    }

    /// Reveals already loaded messages first; fetches an earlier page only when those run out.
    private func showEarlier() async {
        if messages.count > shownMessages { shownMessages += 10; return }
        guard let id = project.slack?.id, let oldest = messages.last?.ts, !loadingEarlier else { return }
        loadingEarlier = true
        defer { loadingEarlier = false }
        do {
            let page = try await app.withSlack { try await $0.historyPage(id, before: oldest, limit: 20) }
            merge(page.messages)
            hasEarlier = page.hasMore
            shownMessages += 10
        } catch { app.report(error) }
    }

    /// What the rail shows: this week's messages, at most six; when the channel has been
    /// quiet all week, only its last message, under a note saying since when.
    private var railPlan: (count: Int, recent: Int, quietSince: Date?) {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let recent = messages.prefix { $0.date >= weekAgo }.count   // newest first
        if recent == 0 { return (min(1, messages.count), 0, messages.first?.date) }
        return (min(recent, 6), recent, nil)
    }

    private var slackSubtitle: String {
        if slackExpanded { return "Conversation" }
        if !loaded { return "Latest messages" }
        let plan = railPlan
        if let since = plan.quietSince {
            return "Quiet since \(since.formatted(.relative(presentation: .named)))"
        }
        return plan.recent == 1 ? "1 message this week" : "\(plan.recent) messages this week"
    }

    private func toggleSlackWide() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            slackExpanded.toggle()
            if slackExpanded { shownMessages = max(shownMessages, 30) }
        }
    }

    private var slackActions: SlackMessageActions {
        SlackMessageActions(
            reply: { m, text in
                guard let id = project.slack?.id else { return }
                try await app.withSlack { try await $0.reply(id, threadTS: m.ts, text: text) }
                await loadSlack()
            },
            react: { m, name, on in
                guard let id = project.slack?.id else { return }
                try await app.withSlack { try await $0.react(id, ts: m.ts, name: name, on: on) }
                await loadSlack()
            },
            replies: { m in
                guard let id = project.slack?.id else { return [] }
                return try await app.withSlack { try await $0.replies(id, threadTS: m.ts) }
            })
    }

    private func loadGitHub() async {
        guard let repo = project.githubRepo, states[.github] == nil else { return }
        do {
            let client = try app.githubClient()
            let refs: [IssueReference]? = project.linear == nil || states[.linear] != nil ? nil : issues
            async let allRuns = client.runs(repo)
            async let recentlyMerged = client.mergedPulls(repo)
            let prs = ProjectPullRequests(pulls: try await client.pulls(repo), issues: refs,
                                          wholeRepository: project.showsWholeRepository)
            pulls = prs.matches
            pullsScoped = prs.scoped
            runs = prs.scoped ? prs.pipeline(from: try await allRuns).latest : try await allRuns
            merged = MergedPull.list(repo: repo, recentlyMerged: try await recentlyMerged, issues: refs,
                                     wholeRepository: project.showsWholeRepository,
                                     open: Set(prs.matches.map(\.pull.number)))
            for m in merged { issueStore.pullsByURL[m.url] = .init(number: m.number, title: m.title ?? "", state: .merged) }
            for p in pulls {
                issueStore.pullsByURL[p.pull.html_url] = .init(number: p.pull.number, title: p.pull.title,
                                                               state: p.pull.draft == true ? .draft : .open)
            }
            lastLoaded[.github] = Date()
            app.succeeded(.github)
        } catch { states[.github] = app.failure(error, .github) }
    }
}
