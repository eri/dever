import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject var app: AppState
    let project: Project
    let edit: () -> Void

    @State private var issues: [LinearIssue] = []
    @State private var messages: [SlackMessage] = []
    @State private var users: [String: String] = [:]
    @State private var pulls: [GitHubPull] = []
    @State private var runs: [GitHubRun] = []
    @State private var errors: [ServiceKind: String] = [:]
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !project.isComplete {
                    Label("Link a Slack channel and a Linear project to start tracking.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                HStack(alignment: .top, spacing: 16) {
                    panel(.linear, title: "Linear issues") { linearPanel }
                    panel(.slack, title: "Slack") { slackPanel }
                }
                if project.githubRepo != nil {
                    panel(.github, title: "GitHub") { githubPanel }
                }
            }
            .padding(20)
        }
        .navigationTitle(project.name)
        .toolbar {
            Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(loading)
            Button("Links…", action: edit)
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            linkChip("number", project.slack.map { "#\($0.name)" },
                     url: project.slack.flatMap { s in app.slack.map { URL(string: "https://\($0.domain).slack.com/archives/\(s.id)")! } })
            linkChip("checklist", project.linear?.name, url: project.linear.flatMap { URL(string: $0.url) })
            linkChip("chevron.left.forwardslash.chevron.right", project.githubRepo,
                     url: project.githubRepo.flatMap { URL(string: "https://github.com/\($0)") })
        }
    }

    @ViewBuilder
    private func linkChip(_ symbol: String, _ text: String?, url: URL?) -> some View {
        if let text {
            if let url { Link(destination: url) { Label(text, systemImage: symbol) } } else { Label(text, systemImage: symbol) }
        } else {
            Label("not linked", systemImage: symbol).foregroundStyle(.secondary)
        }
    }

    private func panel<C: View>(_ s: ServiceKind, title: String, @ViewBuilder content: () -> C) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let e = errors[s] { Text(e).foregroundStyle(.red).font(.callout) }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: s.symbol).font(.headline)
        }
    }

    private var linearPanel: some View {
        let groups = Dictionary(grouping: issues, by: \.state.type)
        let order = ["started", "unstarted", "backlog", "triage", "completed", "canceled"]
        return VStack(alignment: .leading, spacing: 10) {
            if !issues.isEmpty {
                let done = issues.filter { $0.state.type == "completed" }.count
                ProgressView(value: Double(done), total: Double(issues.count)) {
                    Text("\(done)/\(issues.count) done").font(.caption)
                }
            }
            ForEach(order.filter { groups[$0] != nil && !["completed", "canceled"].contains($0) }, id: \.self) { type in
                ForEach(groups[type] ?? []) { issue in
                    HStack {
                        Text(issue.identifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Link(issue.title, destination: URL(string: issue.url)!).lineLimit(1)
                        Spacer()
                        Text(issue.state.name).font(.caption).foregroundStyle(.secondary)
                        if let a = issue.assignee { Text(a.name).font(.caption) }
                    }
                }
            }
        }
    }

    private var slackPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages.prefix(20)) { m in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(m.user.flatMap { users[$0] } ?? m.user ?? "bot").font(.caption.bold())
                        Text(m.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                        if let r = m.reply_count { Text("· \(r) replies").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(m.text ?? "").lineLimit(3)
                }
            }
        }
    }

    private var githubPanel: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Open PRs (\(pulls.count))").font(.subheadline.bold())
                ForEach(pulls) { pr in
                    HStack {
                        Link("#\(pr.number) \(pr.title)", destination: URL(string: pr.html_url)!).lineLimit(1)
                        if pr.draft == true { Text("draft").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(pr.user.login).font(.caption)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Pipeline").font(.subheadline.bold())
                ForEach(runs) { run in
                    HStack {
                        Image(systemName: runSymbol(run)).foregroundStyle(runColor(run))
                        Link("\(run.name ?? "run") · \(run.head_branch ?? "")", destination: URL(string: run.html_url)!)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func runSymbol(_ r: GitHubRun) -> String {
        if r.status != "completed" { return "clock" }
        return r.conclusion == "success" ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private func runColor(_ r: GitHubRun) -> Color {
        if r.status != "completed" { return .orange }
        return r.conclusion == "success" ? .green : .red
    }

    private func load() async {
        loading = true
        defer { loading = false }
        errors = [:]
        async let l: Void = loadLinear()
        async let s: Void = loadSlack()
        async let g: Void = loadGitHub()
        _ = await (l, s, g)
    }

    private func loadLinear() async {
        guard let id = project.linear?.id else { return }
        do { issues = try await app.withLinear { try await $0.issues(projectID: id) } } catch { errors[.linear] = error.localizedDescription }
    }

    private func loadSlack() async {
        guard let id = project.slack?.id else { return }
        do {
            messages = try await app.withSlack { try await $0.history(id) }
            if users.isEmpty { users = (try? await app.withSlack { try await $0.userNames() }) ?? [:] }
        } catch { errors[.slack] = error.localizedDescription }
    }

    private func loadGitHub() async {
        guard let repo = project.githubRepo else { return }
        do {
            let client = try app.githubClient()
            async let p = client.pulls(repo)
            async let r = client.runs(repo)
            (pulls, runs) = try await (p, r)
        } catch { errors[.github] = error.localizedDescription }
    }
}
