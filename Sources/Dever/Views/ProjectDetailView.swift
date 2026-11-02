import SwiftUI

/// One project. Its question: what is left to ship, and what needs closing?
struct ProjectDetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    let project: Project
    let edit: () -> Void

    @State private var issues: [LinearIssue] = []
    @State private var messages: [SlackMessage] = []
    @State private var users: [String: String] = [:]
    @State private var pulls: [ProjectPullRequests.Match] = []
    @State private var pullsScoped = false
    @State private var runs: [GitHubRun] = []
    @State private var merged: [MergedPull] = []
    @State private var errors: [ServiceKind: String] = [:]
    @State private var loading = false
    @State private var loaded = false
    @State private var expanded: Set<String> = []

    private var status: ProjectStatus { project.status(store.snapshots[project.id]) }

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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                titleRow
                // The work on the left; the conversation alongside it, like a right rail.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        workColumn.frame(minWidth: 520)
                        slackPanel.frame(width: 440)
                    }
                    VStack(spacing: 20) { workColumn; slackPanel }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Soot.ground)
        .environment(\.colorScheme, .dark)
        .navigationTitle(project.name)
        .windowTitleHidden()
        .task { await load() }
    }

    private var workColumn: some View {
        VStack(spacing: 20) {
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
                Button { Task { await load() } } label: {
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

    private var deliveryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("Delivery", subtitle: "Linear issues joined with their pull requests")
            if let e = errors[.linear] {
                LoadErrorRow(service: .linear, message: e) { Task { await load() } }
            } else if !loaded {
                Skeleton(height: 12, radius: 2)
                HStack(spacing: 16) { Skeleton(width: 110); Skeleton(width: 90); Skeleton(width: 120) }
            } else if delivery.total == 0 {
                EmptySection(title: "No issues yet", message: "Issues added to this project in Linear appear here.")
            } else {
                DeliveryStrip(delivery: delivery, height: 12)
                DeliveryLegend(delivery: delivery)
                if !toClose.isEmpty { toCloseList }
            }
        }
        .sootPanel()
    }

    private var toCloseList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Merged, still in progress in Linear").font(Theme.smallStrong).foregroundStyle(Theme.text)
                .padding(.bottom, 8)
            ForEach(capped(toClose, key: "close"), id: \.issue.id) { item in
                Rectangle().fill(Theme.rule).frame(height: 1)
                HStack(spacing: 12) {
                    issueID(item.issue)
                    Text(item.issue.title).foregroundStyle(Theme.text).lineLimit(1).help(item.issue.title)
                    Spacer(minLength: 12)
                    if let url = URL(string: item.pull.url) {
                        Link(destination: url) { Text(verbatim: "#\(item.pull.number)").font(Theme.id) }
                            .help("Open the merged pull request")
                    }
                    Text(item.pull.mergedAt.map { "merged \($0.formatted(.relative(presentation: .named)))" } ?? "merged")
                        .font(Theme.small).foregroundStyle(Theme.muted)
                        .frame(width: 130, alignment: .trailing)
                }
                .font(Theme.body)
                .frame(minHeight: 36)
            }
            showAll(toClose.count, key: "close")
        }
    }

    // MARK: Issues

    private var activeIssues: [LinearIssue] { issues.filter { $0.state.type == "started" && !Delivery.isReviewState($0.state.name) } }
    private var reviewIssues: [LinearIssue] { issues.filter { $0.state.type == "started" && Delivery.isReviewState($0.state.name) } }
    private var todoIssues: [LinearIssue] { issues.filter { ["unstarted", "backlog", "triage"].contains($0.state.type) } }
    private var doneIssues: [LinearIssue] { issues.filter { $0.state.type == "completed" } }

    private var issuesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("Issues", subtitle: loaded && !issues.isEmpty
                          ? "\(activeIssues.count) in progress · \(reviewIssues.count) in review · \(todoIssues.count) to do · \(doneIssues.count) done" : nil)
            if project.linear == nil {
                EmptySection(title: "No Linear project", message: "Link one to see its issues here.")
            } else if let e = errors[.linear] {
                LoadErrorRow(service: .linear, message: e) { Task { await load() } }
            } else if !loaded {
                VStack(alignment: .leading, spacing: 8) {
                    Skeleton(width: 110)
                    SkeletonRows(count: 5, leading: 64, trailing: 80)
                }
            } else if issues.isEmpty {
                EmptySection(title: "No issues yet", message: "Issues added to this project in Linear appear here.")
            } else {
                issueGroup("In progress", activeIssues, key: "active")
                issueGroup("In review", reviewIssues, key: "review")
                issueGroup("To do", todoIssues, key: "todo")
                if !doneIssues.isEmpty {
                    DisclosureGroup {
                        issueRows(doneIssues, key: "done")
                    } label: {
                        Text("Done · \(doneIssues.count)").font(Theme.smallStrong).foregroundStyle(Theme.text).monospacedDigit()
                    }
                }
            }
        }
        .sootPanel()
    }

    @ViewBuilder
    private func issueGroup(_ title: String, _ list: [LinearIssue], key: String) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(title) · \(list.count)").font(Theme.smallStrong).foregroundStyle(Theme.text).monospacedDigit()
                    .padding(.bottom, 8)
                issueRows(list, key: key)
            }
        }
    }

    private func issueRows(_ list: [LinearIssue], key: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(capped(list, key: key)) { issue in
                Rectangle().fill(Theme.rule).frame(height: 1)
                HStack(spacing: 12) {
                    issueID(issue)
                    Text(issue.title).foregroundStyle(Theme.text).lineLimit(1).help(issue.title)
                    Spacer(minLength: 12)
                    Text(issue.assignee?.name ?? "Unassigned").font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .font(Theme.body)
                .frame(minHeight: 36)
                .accessibilityElement(children: .combine)
            }
            showAll(list.count, key: key)
        }
    }

    private func issueID(_ issue: LinearIssue) -> some View {
        Group {
            if let url = URL(string: issue.url) {
                Link(destination: url) { Text(issue.identifier) }.help("Open \(issue.identifier) in Linear")
            } else {
                Text(issue.identifier)
            }
        }
        .font(Theme.id)
        .frame(width: 76, alignment: .leading)
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
                                channelID: project.slack?.id, limit: 6)
            }
        }
        .sootPanel()
    }

    private func message(_ m: SlackMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(m.user.flatMap { users[$0] } ?? "Integration").font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Text(m.date.formatted(.relative(presentation: .named))).font(Theme.small).foregroundStyle(Theme.muted)
                if let r = m.reply_count, r > 0 {
                    Text("· ^[\(r) reply](inflect: true)").font(Theme.small).foregroundStyle(Theme.muted)
                }
            }
            Text(m.text ?? "")
                .font(Theme.body)
                .foregroundStyle(Theme.text)
                .lineLimit(3)
                .lineSpacing(2)
                .textSelection(.enabled)
                .help(m.text ?? "")
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: GitHub

    private var githubPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader("GitHub", subtitle: !loaded ? nil
                          : pullsScoped ? "Pull requests linked to this project's Linear issues" : "Whole repository") {
                if let repo = project.githubRepo, let url = URL(string: "https://github.com/\(repo)") {
                    Link("Open on GitHub", destination: url).font(Theme.small)
                }
            }
            if let e = errors[.github] {
                LoadErrorRow(service: .github, message: e) { Task { await load() } }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 32) { openPulls; pipelineRuns }
                    VStack(alignment: .leading, spacing: 20) { openPulls; pipelineRuns }
                }
                mergedPulls
            }
        }
        .sootPanel()
    }

    private var openPulls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(loaded ? "Open · \(pulls.count)" : "Open").font(Theme.smallStrong).foregroundStyle(Theme.text).monospacedDigit()
                .padding(.bottom, 8)
            if !loaded { SkeletonRows(count: 3, leading: 64, trailing: 56) }
            if pulls.isEmpty && loaded {
                Text(pullsScoped ? "No open pull request mentions this project's issues." : "No open pull requests.")
                    .font(Theme.body).foregroundStyle(Theme.muted)
            }
            ForEach(capped(pulls, key: "open")) { match in
                Rectangle().fill(Theme.rule).frame(height: 1)
                pullRow(issue: match.issue, number: match.pull.number, title: match.pull.title,
                        url: match.pull.html_url, trailing: match.pull.draft == true ? "Draft" : match.pull.user.login)
            }
            showAll(pulls.count, key: "open")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pipelineRuns: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pullsScoped ? "Pipeline · latest run per branch" : "Pipeline · recent runs")
                .font(Theme.smallStrong).foregroundStyle(Theme.text)
                .padding(.bottom, 8)
            if !loaded { SkeletonRows(count: 3, leading: 72, trailing: 80) }
            if runs.isEmpty && loaded {
                Text(pullsScoped && pulls.isEmpty ? "No open pull requests, so no runs to show." : "No runs yet.")
                    .font(Theme.body).foregroundStyle(Theme.muted)
            }
            ForEach(runs.prefix(6)) { run in
                Rectangle().fill(Theme.rule).frame(height: 1)
                HStack(spacing: 12) {
                    PipelineBadge(state: .init(run: run)).frame(width: 96, alignment: .leading)
                    if let url = URL(string: run.html_url) {
                        Link(run.name ?? "Workflow run", destination: url).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(run.head_branch ?? "").font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1)
                        .help(run.head_branch ?? "")
                }
                .font(Theme.body)
                .frame(minHeight: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mergedPulls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(loaded ? "Recently merged · \(merged.count)" : "Recently merged").font(Theme.smallStrong).foregroundStyle(Theme.text).monospacedDigit()
                .padding(.bottom, 8)
            if !loaded { SkeletonRows(count: 4, leading: 64, trailing: 96) }
            if merged.isEmpty && loaded {
                Text(pullsScoped ? "No merged pull request is linked to this project's issues." : "No recently merged pull requests.")
                    .font(Theme.body).foregroundStyle(Theme.muted)
            }
            ForEach(capped(merged, key: "merged")) { item in
                Rectangle().fill(Theme.rule).frame(height: 1)
                pullRow(issue: item.issue, number: item.number, title: item.title ?? "Pull request #" + String(item.number),
                        url: item.url, trailing: item.mergedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "")
            }
            showAll(merged.count, key: "merged")
        }
    }

    private func pullRow(issue: String?, number: Int, title: String, url: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            Group {
                if let issue, let link = issues.first(where: { $0.identifier == issue }).flatMap({ URL(string: $0.url) }) {
                    Link(destination: link) { Text(issue) }.help("Open \(issue) in Linear")
                } else {
                    Text(issue ?? "").foregroundStyle(Theme.muted)
                }
            }
            .font(Theme.id)
            .frame(width: 76, alignment: .leading)
            Text(verbatim: "#\(number)").font(Theme.id).foregroundStyle(Theme.muted).frame(width: 52, alignment: .leading)
            if let link = URL(string: url) {
                Link(title, destination: link).foregroundStyle(Theme.text).lineLimit(1).help(title)
            }
            Spacer(minLength: 12)
            Text(trailing).font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .font(Theme.body)
        .frame(minHeight: 36)
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
            Button(expanded.contains(key) ? "Show fewer" : "Show all \(count)") {
                if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
            }
            .buttonStyle(.link)
            .font(Theme.small)
            .padding(.top, 8)
        }
    }

    // MARK: Loading

    private func load() async {
        loading = true
        defer { loading = false; loaded = true }
        errors = [:]
        async let s: Void = loadSlack()
        // GitHub needs the Linear issues to tell which pull requests belong to the project.
        await loadLinear()
        await loadGitHub()
        await s
    }

    private func loadLinear() async {
        guard let id = project.linear?.id else { return }
        do { issues = try await app.withLinear { try await $0.issues(projectID: id) } } catch { errors[.linear] = error.localizedDescription }
    }

    private func loadSlack() async {
        guard let id = project.slack?.id else { return }
        do {
            messages = try await app.withSlack { try await $0.history(id) }
                .filter { $0.subtype != "channel_join" && $0.subtype != "channel_leave" }
            if users.isEmpty { users = (try? await app.withSlack { try await $0.userNames() }) ?? [:] }
        } catch { errors[.slack] = error.localizedDescription }
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
        } catch { errors[.github] = error.localizedDescription }
    }
}
