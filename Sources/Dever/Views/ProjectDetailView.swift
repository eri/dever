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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulls: [ProjectPullRequests.Match] = []
    @State private var pullsScoped = false
    @State private var runs: [GitHubRun] = []
    @State private var merged: [MergedPull] = []
    @State private var errors: [ServiceKind: String] = [:]
    @State private var loading = false
    @State private var loaded = false
    @State private var expanded: Set<String> = []
    @State private var issueTab: IssueTab = .active
    @State private var pullTab: PullTab = .merged

    private var status: ProjectStatus { project.status(store.snapshots[project.id]) }

    private var issues: [LinearIssue] { project.linear.map { issueStore.issues(project: $0.id) } ?? [] }

    private var delivery: Delivery {
        Delivery(issues: issues.map { ($0.identifier, $0.state.type, $0.state.name) },
                 openPR: Set(pulls.compactMap(\.issue)),
                 mergedPR: Set(merged.compactMap(\.issue)))
    }

    /// Issues whose code is merged while the ticket still says work is ongoing (review
    /// and QA states excluded): the screen's finding and its action.
    private var toClose: [(issue: LinearIssue, pull: MergedPull)] {
        issues.compactMap { issue in
            guard let pull = merged.first(where: { $0.issue == issue.identifier }),
                  Delivery.isBehind(stateType: issue.state.type, stateName: issue.state.name, merged: true) else { return nil }
            return (issue, pull)
        }
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
        .navigationTitle(project.name)
        .windowTitleHidden()
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSlackWide)) { _ in
            slackExpanded.toggle()
            if slackExpanded { shownMessages = max(shownMessages, 30) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFirstIssue)) { _ in
            if let first = issues(in: currentIssueTab).first {
                NotificationCenter.default.post(name: .openIssue, object: IssueRoute(project: project, issue: first))
            }
        }
    }

    private var workColumn: some View {
        VStack(spacing: 16) {
            if project.linear != nil { deliveryPanel }
            issuesPanel
            if project.githubRepo != nil { githubPanel }
        }
    }

    // MARK: Title row

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(project.name).font(.system(size: 32, weight: .semibold)).tracking(-0.8)
                        .foregroundStyle(Soot.ink)
                        .accessibilityAddTraits(.isHeader)
                    if status == .loading { Skeleton(width: 72, height: 20, radius: 4) } else { StatusBadge(status: status) }
                }
                if loaded || !project.isComplete {
                    Text(finding).font(.system(size: 15)).foregroundStyle(Soot.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Skeleton(width: 280, height: 14).padding(.vertical, 2)
                }
                linkRow
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Button { Task { await load(force: true) } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(Theme.muted)
                }
                .buttonStyle(.borderless)
                .help("Refresh this project")
                .accessibilityLabel("Refresh this project")
                .keyboardShortcut("r")
                .disabled(loading)
                Button("Edit links…", action: edit).buttonStyle(QuietButton())
                if !toClose.isEmpty, let url = project.linear.flatMap({ URL(string: $0.url) }) {
                    Link(destination: url) { Text("Update \(toClose.count) in Linear") }
                        .buttonStyle(LimeButton())
                        .help("Open the project in Linear to move these merged issues forward")
                }
            }
        }
    }

    private var finding: String {
        if !project.isComplete { return "Link a Slack channel and a Linear project to start tracking." }
        if !toClose.isEmpty {
            return Plural.text("^[\(toClose.count) issue](inflect: true) merged in code but still marked in progress in Linear.")
        }
        if loaded, delivery.total > 0 {
            let left = delivery.total - delivery.shipped
            return left == 0 ? "Every issue has shipped."
                : Plural.text("\(delivery.shipped) of ^[\(delivery.total) issue](inflect: true) shipped, \(left) to go.")
        }
        return " "
    }

    private var slackURL: URL? {
        guard let channel = project.slack, let slack = app.slack else { return nil }
        return URL(string: "https://\(slack.domain).slack.com/archives/\(channel.id)")
    }

    private var linkRow: some View {
        HStack(spacing: 16) {
            if let channel = project.slack, let url = slackURL {
                Link(destination: url) { Label { Text("#\(channel.name)") } icon: { BrandLogo(service: .slack, size: 12) } }
            }
            if let linear = project.linear, let url = URL(string: linear.url) {
                Link(destination: url) { Label { Text(linear.name) } icon: { BrandLogo(service: .linear, size: 12) } }
            }
            if let repo = project.githubRepo, let url = URL(string: "https://github.com/\(repo)") {
                Link(destination: url) { Label { Text(repo) } icon: { BrandLogo(service: .github, size: 12) } }
            }
        }
        .font(Theme.small)
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
    }

    // MARK: Delivery (the signature block)

    private var linearURL: URL? { project.linear.flatMap { URL(string: $0.url) } }

    private var deliveryPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelHeader(service: .linear, title: "Delivery", subtitle: "Issues joined with their pull requests")
            if let e = errors[.linear] {
                LoadErrorRow(service: .linear, message: e) { Task { await load() } }
            } else if !loaded {
                HStack(alignment: .lastTextBaseline, spacing: 10) { Skeleton(width: 90, height: 34); Skeleton(width: 120) }
                Skeleton(height: 10, radius: 5)
            } else if delivery.total == 0 {
                QuietEmpty(symbol: "tray", text: "No issues in this project yet")
            } else {
                // Headline figure and the stage counts on one line, the bar under them.
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(Double(delivery.shipped) / Double(delivery.total), format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 34, weight: .semibold)).tracking(-1).foregroundStyle(Soot.ink).monospacedDigit()
                    Text("\(delivery.shipped) of \(delivery.total) shipped").font(.system(size: 14)).foregroundStyle(Soot.muted)
                        .monospacedDigit()
                    Spacer(minLength: 16)
                    HStack(spacing: 20) {
                        ForEach(Delivery.Stage.allCases.filter { delivery.count($0) > 0 }, id: \.self) { stage in
                            HStack(spacing: 6) {
                                Circle().fill(DeliveryStrip.color(stage)).frame(width: 7, height: 7)
                                Text("\(delivery.count(stage))").font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Soot.ink).monospacedDigit()
                                Text(stage.label).font(.system(size: 12)).foregroundStyle(Soot.muted)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                deliveryBar
                if !toClose.isEmpty { toCloseList }
            }
        }
        .sootPanel()
    }

    /// Rounded segments with gaps, one per stage, proportional to its issues.
    private var deliveryBar: some View {
        GeometryReader { geo in
            let stages = Delivery.Stage.allCases.filter { delivery.count($0) > 0 }
            let gap: CGFloat = 4
            let usable = geo.size.width - gap * CGFloat(max(stages.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(stages, id: \.self) { stage in
                    Capsule().fill(DeliveryStrip.color(stage))
                        .frame(width: max(10, usable * CGFloat(delivery.count(stage)) / CGFloat(max(delivery.total, 1))))
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private var toCloseList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Merged, still in progress in Linear").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                .padding(.leading, 12)
            ForEach(capped(toClose, key: "close"), id: \.issue.id) { item in
                TileRow(url: URL(string: item.issue.url)) {
                    IDPill(text: item.issue.identifier)
                    Text(item.issue.title).font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1)
                    Spacer(minLength: 12)
                    Text(item.pull.mergedAt.map { "merged \($0.formatted(.relative(presentation: .named)))" } ?? "merged")
                        .font(.system(size: 12)).foregroundStyle(Soot.muted)
                }
            }
            showAll(toClose.count, key: "close")
        }
        .padding(8)
        .background(Soot.ground.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Issues

    private var activeIssues: [LinearIssue] { issues.filter { $0.state.type == "started" && !Delivery.isReviewState($0.state.name) } }
    private var reviewIssues: [LinearIssue] { issues.filter { $0.state.type == "started" && Delivery.isReviewState($0.state.name) } }
    private var todoIssues: [LinearIssue] { issues.filter { ["unstarted", "backlog", "triage"].contains($0.state.type) } }
    private var doneIssues: [LinearIssue] { issues.filter { $0.state.type == "completed" } }

    private enum IssueTab: Hashable { case active, review, todo, done }

    private var issueTabs: [(label: String, count: Int, tab: IssueTab)] {
        [("In progress", activeIssues.count, IssueTab.active), ("In review", reviewIssues.count, .review),
         ("To do", todoIssues.count, .todo), ("Done", doneIssues.count, .done)].filter { $0.1 > 0 }
    }

    /// The chosen tab, or the first one that has issues.
    private var currentIssueTab: IssueTab { issueTabs.contains { $0.tab == issueTab } ? issueTab : (issueTabs.first?.tab ?? .active) }

    private func issues(in tab: IssueTab) -> [LinearIssue] {
        switch tab {
        case .active: activeIssues
        case .review: reviewIssues
        case .todo: todoIssues
        case .done: doneIssues
        }
    }

    private var issuesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(service: .linear, title: "Issues", subtitle: project.linear?.name, link: linearURL)
            if project.linear == nil {
                QuietEmpty(symbol: "link", text: "Link a Linear project to see its issues")
            } else if let e = errors[.linear] {
                LoadErrorRow(service: .linear, message: e) { Task { await load() } }
            } else if !loaded {
                HStack(spacing: 6) { ForEach(0..<3, id: \.self) { _ in Skeleton(width: 96, height: 30, radius: 15) } }
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 12) {
                        Skeleton(width: 64, height: 20, radius: 5)
                        Skeleton(width: [280, 220, 320, 250, 200][i], height: 12)
                        Spacer()
                        Skeleton(width: 22, height: 22, radius: 11)
                    }
                    .padding(.horizontal, 12).frame(height: 46)
                }
            } else if issues.isEmpty {
                QuietEmpty(symbol: "tray", text: "No issues in this project yet")
            } else {
                CountTabs(tabs: issueTabs, selection: Binding(get: { currentIssueTab }, set: { issueTab = $0 }))
                let list = issues(in: currentIssueTab)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(capped(list, key: "issues")) { issue in
                        TileLink(value: IssueRoute(project: project, issue: issue)) { IssueRow(issue: issue) }
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Opens the issue")
                    }
                    showAll(list.count, key: "issues")
                }
            }
        }
        .sootPanel()
    }

    // MARK: Slack

    private var slackPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                BrandLogo(service: .slack, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.slack.map { "#\($0.name)" } ?? "Slack").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Soot.ink).accessibilityAddTraits(.isHeader)
                    Text("Latest messages").font(.system(size: 12)).foregroundStyle(Soot.muted)
                }
                Spacer()
                if let url = slackURL {
                    Link(destination: url) { HStack(spacing: 4) { Text("Open"); Image(systemName: "arrow.up.right") } }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
                        .help("Open the channel in Slack")
                }
                if project.slack != nil {
                    // Wide view: a labelled way back, not only a glyph, since the work column is gone.
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                            slackExpanded.toggle()
                            if slackExpanded { shownMessages = max(shownMessages, 30) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: slackExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .semibold))
                            if slackExpanded { Text("Back to project") }
                        }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                        .padding(.horizontal, slackExpanded ? 12 : 0)
                        .frame(minWidth: 30, minHeight: 30)
                        .background(Soot.ground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .modifier(FocusOutline(radius: 15))
                    .help(slackExpanded ? "Back to the project (⌘⇧E)" : "Read the conversation full width (⌘⇧E)")
                    .accessibilityLabel(slackExpanded ? "Back to the project" : "Read the conversation full width")
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                }
            }
            if project.slack == nil {
                EmptySection(title: "No Slack channel", message: "Link a channel to follow its conversation here.")
            } else if let e = errors[.slack] {
                LoadErrorRow(service: .slack, message: e) { Task { await load() } }
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
                                channelID: project.slack?.id, channelName: project.slack?.name, shown: shownMessages,
                                hasEarlier: hasEarlier, loadingEarlier: loadingEarlier,
                                wide: slackExpanded,
                                showEarlier: { Task { await showEarlier() } },
                                actions: slackActions)
            }
        }
        .sootPanel()
    }

    // MARK: GitHub

    private enum PullTab: Hashable { case merged, open, pipeline }

    private var pullTabs: [(label: String, count: Int, tab: PullTab)] {
        [("Merged", merged.count, PullTab.merged), ("Open", pulls.count, .open), ("Pipeline", runs.count, .pipeline)]
    }

    private var githubPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(service: .github, title: "Pull requests",
                        subtitle: loaded ? (pullsScoped ? "Linked to this project's issues" : "Whole repository") : nil,
                        link: project.githubRepo.flatMap { URL(string: "https://github.com/\($0)") })
            if let e = errors[.github] {
                LoadErrorRow(service: .github, message: e) { Task { await load() } }
            } else if !loaded {
                HStack(spacing: 6) { ForEach(0..<3, id: \.self) { _ in Skeleton(width: 90, height: 30, radius: 15) } }
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 12) {
                        Skeleton(width: 18, height: 18, radius: 9)
                        VStack(alignment: .leading, spacing: 6) {
                            Skeleton(width: [300, 240, 280, 220][i], height: 12)
                            Skeleton(width: 140, height: 9)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12).frame(height: 56)
                }
            } else {
                CountTabs(tabs: pullTabs, selection: $pullTab)
                VStack(alignment: .leading, spacing: 2) {
                    switch pullTab {
                    case .merged:
                        if merged.isEmpty { QuietEmpty(symbol: "arrow.triangle.merge", text: "Nothing merged yet") }
                        ForEach(capped(merged, key: "merged")) { item in
                            pullRow(symbol: "arrow.triangle.merge", tint: Soot.lime,
                                    title: item.title ?? "Pull request #\(item.number)", number: item.number,
                                    issue: item.issue, url: item.url,
                                    trailing: item.mergedAt.map { $0.formatted(.relative(presentation: .named)) })
                        }
                        showAll(merged.count, key: "merged")
                    case .open:
                        if pulls.isEmpty {
                            QuietEmpty(symbol: "arrow.triangle.pull",
                                       text: pullsScoped ? "No open pull request on this project's issues" : "No open pull requests")
                        }
                        ForEach(capped(pulls, key: "open")) { match in
                            pullRow(symbol: "arrow.triangle.pull", tint: Theme.chart2, title: match.pull.title,
                                    number: match.pull.number, issue: match.issue, url: match.pull.html_url,
                                    trailing: match.pull.draft == true ? "Draft" : match.pull.user.login)
                        }
                        showAll(pulls.count, key: "open")
                    case .pipeline:
                        if runs.isEmpty { QuietEmpty(symbol: "bolt.horizontal", text: "No runs to show") }
                        ForEach(runs.prefix(8)) { run in
                            TileRow(url: URL(string: run.html_url)) {
                                PipelineBadge(state: .init(run: run)).font(.system(size: 13)).frame(width: 90, alignment: .leading)
                                Text(run.name ?? "Workflow run").font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1)
                                Spacer(minLength: 12)
                                Text(run.head_branch ?? "").font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .sootPanel()
    }

    /// Two lines: what changed, then number, kind and linked issue.
    private func pullRow(symbol: String, tint: Color, title: String, number: Int, issue: String?,
                         url: String, trailing: String?) -> some View {
        let parts = PullTitle.split(title)
        return TileRow(url: URL(string: url)) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint).frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(parts.title).font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1).help(title)
                HStack(spacing: 6) {
                    Text(verbatim: "#\(number)")
                    if let kind = parts.kind { Text("·"); Text(kind) }
                }
                .font(.system(size: 12)).foregroundStyle(Soot.muted)
            }
            Spacer(minLength: 12)
            if let issue { IDPill(text: issue) }
            if let trailing {
                Text(trailing).font(.system(size: 12)).foregroundStyle(Soot.muted).frame(minWidth: 70, alignment: .trailing)
            }
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
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

    private func load(force: Bool = false) async {
        loading = true
        defer { loading = false; loaded = true }
        errors = [:]
        async let s: Void = loadSlack()
        // GitHub needs the Linear issues to tell which pull requests belong to the project.
        await loadLinear(force: force)
        await loadGitHub()
        await s
    }

    private func loadLinear(force: Bool) async {
        guard let id = project.linear?.id else { return }
        do { _ = try await issueStore.load(project: id, force: force, app: app) } catch { errors[.linear] = error.localizedDescription }
    }

    private func loadSlack() async {
        guard let id = project.slack?.id else { return }
        do {
            let page = try await app.withSlack { try await $0.historyPage(id, limit: 20) }
            merge(page.messages)
            if messages.count <= 20 { hasEarlier = page.hasMore }
            if let team = app.slack?.teamID {
                // One users.list per quarter hour across the app, not one per visit.
                users = try await app.withSlack { try await SlackDirectory.shared.users(team: team, via: $0) }
            }
            let authors = Set(messages.prefix(shownMessages).compactMap(\.user)).compactMap { users[$0] }
            Task.detached(priority: .utility) { await SlackMediaCache.shared.prefetchAvatars(authors) }
        } catch { errors[.slack] = error.localizedDescription }
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
        guard let repo = project.githubRepo else { return }
        do {
            let client = try app.githubClient()
            let refs: [IssueReference]? = project.linear == nil || errors[.linear] != nil ? nil : issues
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
        } catch { errors[.github] = error.localizedDescription }
    }
}
