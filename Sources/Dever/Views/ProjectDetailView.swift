import SwiftUI

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
    @State private var merged: [MergedPull] = []
    @State private var showAllMerged = false
    @State private var runs: [GitHubRun] = []
    @State private var errors: [ServiceKind: String] = [:]
    @State private var loading = false
    @State private var loaded = false

    private var status: ProjectStatus { project.status(store.snapshots[project.id]) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                // Two columns while they fit, stacked otherwise.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        linearSection.frame(minWidth: 360)
                        slackSection.frame(minWidth: 320)
                    }
                    VStack(spacing: 16) {
                        linearSection
                        slackSection
                    }
                }
                if project.githubRepo != nil { githubSection }
            }
            .padding(24)
        }
        .navigationTitle(project.name)
        .navigationSubtitle(loading ? "Refreshing…" : "")
        .toolbar {
            Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Refresh this project")
                .keyboardShortcut("r")
                .disabled(loading)
            Button(action: edit) { Label("Edit links…", systemImage: "link") }
                .help("Change the linked Slack channel, Linear project and repository")
        }
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                StatusBadge(status: status)
                linkButton(.slack, project.slack.map { "#\($0.name)" }, url: slackURL)
                linkButton(.linear, project.linear?.name, url: project.linear.flatMap { URL(string: $0.url) })
                linkButton(.github, project.githubRepo, url: project.githubRepo.flatMap { URL(string: "https://github.com/\($0)") })
            }
            if !project.isComplete {
                HStack(spacing: 12) {
                    Label {
                        Text("Link a Slack channel and a Linear project to start tracking.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Button("Edit links…", action: edit)
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var slackURL: URL? {
        guard let channel = project.slack, let slack = app.slack else { return nil }
        return URL(string: "https://\(slack.domain).slack.com/archives/\(channel.id)")
    }

    @ViewBuilder
    private func linkButton(_ service: ServiceKind, _ text: String?, url: URL?) -> some View {
        if let text, let url {
            Link(destination: url) { Label(text, systemImage: service.symbol).lineLimit(1) }
                .help("Open \(text) in \(service.label)")
        } else if text == nil, service != .github {
            Label("No \(service.label)", systemImage: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    // MARK: Linear

    private var activeIssues: [LinearIssue] { issues.filter { $0.state.type == "started" } }
    private var todoIssues: [LinearIssue] { issues.filter { ["unstarted", "backlog", "triage"].contains($0.state.type) } }
    private var doneIssues: [LinearIssue] { issues.filter { $0.state.type == "completed" } }

    private var linearSection: some View {
        SectionCard("Linear", symbol: ServiceKind.linear.symbol) {
            if let url = project.linear.flatMap({ URL(string: $0.url) }) {
                Link("Open in Linear", destination: url).font(.callout)
            }
        } content: {
            if project.linear == nil {
                EmptySection(title: "No Linear project", message: "Link a Linear project to see its issues here.")
                Button("Edit links…", action: edit)
            } else if let e = errors[.linear] {
                LoadErrorRow(service: .linear, message: e) { Task { await load() } }
            } else if issues.isEmpty {
                if loaded {
                    EmptySection(title: "No issues yet", message: "Issues added to this project in Linear appear here.")
                } else {
                    ProgressView().controlSize(.small).accessibilityLabel("Loading issues")
                }
            } else {
                let total = activeIssues.count + todoIssues.count + doneIssues.count
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(total == 0 ? 0 : Double(doneIssues.count) / Double(total), format: .percent.precision(.fractionLength(0)))
                            .font(.title2.weight(.semibold)).monospacedDigit()
                        Text("\(doneIssues.count) of ^[\(total) issue](inflect: true) done")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    ProgressView(value: Double(doneIssues.count), total: Double(max(total, 1)))
                        .accessibilityLabel("Progress")
                }
                issueGroup("In progress", activeIssues)
                issueGroup("To do", todoIssues)
                if !doneIssues.isEmpty {
                    DisclosureGroup {
                        issueList(doneIssues)
                    } label: {
                        Text("Done · \(doneIssues.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func issueGroup(_ title: String, _ list: [LinearIssue]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(title) · \(list.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    .accessibilityAddTraits(.isHeader)
                issueList(list)
            }
        }
    }

    private func issueList(_ list: [LinearIssue]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(list) { issue in
                HStack(spacing: 8) {
                    Text(issue.identifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                    if let url = URL(string: issue.url) {
                        Link(issue.title, destination: url).lineLimit(1).help(issue.title)
                    } else {
                        Text(issue.title).lineLimit(1).help(issue.title)
                    }
                    Spacer(minLength: 8)
                    Text(issue.assignee?.name ?? "Unassigned").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Slack

    private var slackSection: some View {
        SectionCard("Slack", symbol: ServiceKind.slack.symbol) {
            if let url = slackURL { Link("Open in Slack", destination: url).font(.callout) }
        } content: {
            if project.slack == nil {
                EmptySection(title: "No Slack channel", message: "Link a channel to follow its conversation here.")
                Button("Edit links…", action: edit)
            } else if let e = errors[.slack] {
                LoadErrorRow(service: .slack, message: e) { Task { await load() } }
            } else if messages.isEmpty {
                if loaded {
                    EmptySection(title: "No messages yet", message: "Messages posted in #\(project.slack?.name ?? "") appear here.")
                } else {
                    ProgressView().controlSize(.small).accessibilityLabel("Loading messages")
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(messages.prefix(20)) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(m.user.flatMap { users[$0] } ?? "Integration").font(.callout.weight(.semibold))
                                Text(m.date.formatted(.relative(presentation: .named)))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let r = m.reply_count, r > 0 {
                                    Text("· ^[\(r) reply](inflect: true)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(m.text ?? "")
                                .lineLimit(4)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .help(m.text ?? "")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: GitHub

    private var githubSection: some View {
        SectionCard("GitHub", symbol: ServiceKind.github.symbol) {
            if let repo = project.githubRepo, let url = URL(string: "https://github.com/\(repo)") {
                Link("Open on GitHub", destination: url).font(.callout)
            }
        } content: {
            if let e = errors[.github] {
                LoadErrorRow(service: .github, message: e) { Task { await load() } }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 32) { pullList; runList }
                    VStack(alignment: .leading, spacing: 16) { pullList; runList }
                }
                mergedList
            }
        }
    }

    private var pullList: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open pull requests · \(pulls.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(pullsScoped ? "Linked to this project's Linear issues" : "Whole repository")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if pulls.isEmpty && loaded {
                Text(pullsScoped
                     ? "No open pull request mentions this project's issues. Name branches after the Linear issue (e.g. its suggested branch) to link them."
                     : "No open pull requests.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(pulls) { match in
                let pr = match.pull
                HStack(spacing: 8) {
                    if let issue = match.issue {
                        if let url = issues.first(where: { $0.identifier == issue }).flatMap({ URL(string: $0.url) }) {
                            Link(issue, destination: url).font(.caption.monospaced()).help("Open \(issue) in Linear")
                        } else {
                            Text(issue).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    Text("#\(pr.number)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    if let url = URL(string: pr.html_url) {
                        Link(pr.title, destination: url).lineLimit(1).help(pr.title)
                    }
                    if pr.draft == true { Text("Draft").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 8)
                    Text(pr.user.login).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runList: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pipeline").font(.subheadline.weight(.semibold))
                Text(pullsScoped ? "Latest run of each pull request branch" : "Recent runs, all branches")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if runs.isEmpty && loaded {
                Text(pullsScoped && pulls.isEmpty ? "No open pull requests, so no runs to show."
                     : pullsScoped ? "No runs on these branches yet." : "No workflow runs yet.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(runs.prefix(8)) { run in
                HStack(spacing: 8) {
                    PipelineBadge(state: .init(run: run)).font(.caption)
                    if let url = URL(string: run.html_url) {
                        Link(run.name ?? "Workflow run", destination: url).lineLimit(1)
                    }
                    Text(run.head_branch ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mergedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recently merged · \(merged.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(pullsScoped ? "Linked to this project's Linear issues" : "Whole repository")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if merged.isEmpty && loaded {
                Text(pullsScoped ? "No merged pull request is linked to this project's issues."
                                 : "No recently merged pull requests.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(showAllMerged ? merged : Array(merged.prefix(8))) { item in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.merge").foregroundStyle(.purple).accessibilityHidden(true)
                    if let issue = item.issue {
                        if let url = issues.first(where: { $0.identifier == issue }).flatMap({ URL(string: $0.url) }) {
                            Link(issue, destination: url).font(.caption.monospaced()).help("Open \(issue) in Linear")
                        } else {
                            Text(issue).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    Text("#\(item.number)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    if let url = URL(string: item.url) {
                        Link(item.title ?? "Pull request #\(item.number)", destination: url)
                            .lineLimit(1).help(item.title ?? "Linked in Linear; older than the recent history Dever scans on GitHub")
                    }
                    Spacer(minLength: 8)
                    if let date = item.mergedAt {
                        Text(date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if merged.count > 8 {
                Button(showAllMerged ? "Show fewer" : "Show all \(merged.count)") { showAllMerged.toggle() }
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
