import Foundation

/// Cross-service snapshot of one project, as shown on the overview.
struct ProjectSnapshot {
    struct LinearStats {
        var total = 0
        var done = 0
        var inProgress = 0
        var todo = 0
        var lead: String?
        var targetDate: Date?

        var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    struct SlackStats {
        var messagesThisWeek = 0
        var lastActivity: Date?
    }

    struct GitHubStats {
        var openPRs = 0
        var pipeline: PipelineState = .unknown
        /// Default branch when unscoped; nil when the pipeline aggregates the project's PR branches.
        var branch: String?
        /// True when PRs and pipeline are limited to the project's Linear issues.
        var scoped = false
        /// Open Linear issues whose pull request is already merged (ticket left behind).
        var mergedButOpen: [String] = []
        /// Issues with an open / merged pull request, for the delivery strip.
        var openPRIssues: Set<String> = []
        var mergedPRIssues: Set<String> = []
    }

    enum PipelineState { case passing, failing, running, unknown }

    var linear: LinearStats?
    var slack: SlackStats?
    var github: GitHubStats?
    /// Issues by delivery stage (Linear joined with GitHub); nil without Linear.
    var delivery: Delivery?
    /// Why a service has no data: never connected, rejected token, offline or a failure.
    var errors: [ServiceKind: ServiceState] = [:]
    var updatedAt = Date()

    /// Services the user still has to connect (or reconnect) for this project.
    var unconnected: [ServiceKind] {
        errors.filter { $0.value.needsConnecting }.keys.sorted { $0.rawValue < $1.rawValue }
    }
}

/// Overall state of a project, derived from its links and its snapshot.
enum ProjectStatus: Int, Comparable {
    case needsAttention, incomplete, notConnected, quiet, onTrack, loading

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .needsAttention: "Needs attention"
        case .incomplete: "Incomplete"
        case .notConnected: "Not connected"
        case .quiet: "Quiet"
        case .onTrack: "On track"
        case .loading: "Loading"
        }
    }
}

extension Project {
    /// Number of days without Slack activity after which a project is "quiet".
    static let quietAfterDays = 14

    /// Human-readable reasons behind the status, most important first.
    func signals(_ s: ProjectSnapshot?) -> [String] {
        var out: [String] = []
        if slack == nil { out.append("No Slack channel") }
        if linear == nil { out.append("No Linear project") }
        guard let s else { return out }
        if s.github?.pipeline == .failing { out.append("Pipeline failing") }
        if let target = s.linear?.targetDate, target < Calendar.current.startOfDay(for: Date()),
           let l = s.linear, l.done < l.total {
            out.append("Past target date")
        }
        if let last = s.slack?.lastActivity,
           Date().timeIntervalSince(last) > Double(Self.quietAfterDays) * 86_400 {
            out.append("No Slack activity for \(Int(Date().timeIntervalSince(last) / 86_400)) days")
        }
        if let stale = s.github?.mergedButOpen, !stale.isEmpty {
            out.append(Plural.text("^[\(stale.count) merged issue](inflect: true) still marked in progress"))
        }
        for (service, state) in s.errors.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            switch state {
            case .notConnected: out.append("Connect \(service.label) to see it here")
            case .unauthorized: out.append("\(service.label) needs reconnecting")
            case .offline: out.append("Offline: \(service.label) data is from the last load")
            case .failed: out.append("Couldn't reach \(service.label)")
            }
        }
        return out
    }

    /// True while a tool this project depends on (Slack or Linear) has no working token.
    func lacksConnection(_ s: ProjectSnapshot) -> Bool {
        (slack != nil && s.errors[.slack]?.needsConnecting == true)
            || (linear != nil && s.errors[.linear]?.needsConnecting == true)
    }

    func status(_ s: ProjectSnapshot?) -> ProjectStatus {
        guard let s else { return isComplete ? .loading : .incomplete }
        if s.github?.pipeline == .failing { return .needsAttention }
        if let target = s.linear?.targetDate, target < Calendar.current.startOfDay(for: Date()),
           let l = s.linear, l.done < l.total {
            return .needsAttention
        }
        if s.github?.mergedButOpen.isEmpty == false { return .needsAttention }
        if !isComplete { return .incomplete }
        // Nothing to judge from: say so instead of "On track".
        if lacksConnection(s) { return .notConnected }
        if let last = s.slack?.lastActivity,
           Date().timeIntervalSince(last) > Double(Self.quietAfterDays) * 86_400 {
            return .quiet
        }
        return .onTrack
    }
}

/// Loads and caches project snapshots; kept alive for the whole app session.
@MainActor
final class OverviewStore: ObservableObject {
    @Published private(set) var snapshots: [UUID: ProjectSnapshot] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    /// Snapshots older than this are refreshed when the overview appears.
    static let staleAfter: TimeInterval = 5 * 60

    var isStale: Bool { lastRefresh.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? true }

    private var autoRefresh: Task<Void, Never>?

    /// Keeps snapshots fresh (and notifications flowing) for as long as the app runs,
    /// even with its window closed.
    func startAutoRefresh(_ app: AppState) {
        guard autoRefresh == nil else { return }
        autoRefresh = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isStale { await self.refresh(app) }
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    func refresh(_ app: AppState) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = Date() }

        let projects = app.projects
        let repos = Result { RepoCache(client: try app.githubClient()) }
        // A few projects at a time keeps us well under the Slack/GitHub rate limits.
        await withTaskGroup(of: (UUID, ProjectSnapshot).self) { group in
            var pending = projects.makeIterator()
            for _ in 0..<4 {
                guard let p = pending.next() else { break }
                group.addTask { await (p.id, Self.load(p, app, repos)) }
            }
            for await (id, snapshot) in group {
                snapshots[id] = snapshot
                if let p = pending.next() { group.addTask { await (p.id, Self.load(p, app, repos)) } }
            }
        }
        let ids = Set(projects.map(\.id))
        snapshots = snapshots.filter { ids.contains($0.key) }
        Notifier.shared.process(projects: projects, snapshots: snapshots)
        // Previews ride the same cycle, after the snapshots so the rows fill in first.
        await PreviewStore.shared.refreshAll(projects, app: app)
    }

    private static func load(_ p: Project, _ app: AppState, _ repos: Result<RepoCache, Error>) async -> ProjectSnapshot {
        var s = ProjectSnapshot()
        async let slack = loadSlack(p, app)
        // GitHub waits for Linear: the project's issues decide which PRs belong to it.
        var issues: [LinearClient.ProjectSummary.Issue]?
        switch await loadLinear(p, app) {
        case .success(let v):
            s.linear = v?.stats
            issues = v?.issues
        case .failure(let e):
            s.errors[.linear] = await app.failure(e, .linear)
        }
        let projectIssues = issues
        async let github = loadGitHub(p, repos, issues: projectIssues)
        switch await slack {
        case .success(let v): s.slack = v
        case .failure(let e): s.errors[.slack] = await app.failure(e, .slack)
        }
        switch await github {
        case .success(let v):
            s.github = v
            if v != nil { await app.succeeded(.github) }
        case .failure(let e): s.errors[.github] = await app.failure(e, .github)
        }
        if let issues {
            s.delivery = Delivery(issues: issues.map { ($0.identifier, $0.state.type, $0.state.name) },
                                  openPR: s.github?.openPRIssues ?? [],
                                  mergedPR: s.github?.mergedPRIssues ?? [])
        }
        return s
    }

    private static func loadLinear(_ p: Project, _ app: AppState)
        async -> Result<(stats: ProjectSnapshot.LinearStats, issues: [LinearClient.ProjectSummary.Issue])?, Error> {
        guard let id = p.linear?.id else { return .success(nil) }
        do {
            let summary = try await app.withLinear { try await $0.projectSummary(id: id) }
            var stats = ProjectSnapshot.LinearStats()
            for issue in summary.issues.nodes {
                switch issue.state.type {
                case "canceled": continue
                case "completed": stats.done += 1
                case "started": stats.inProgress += 1
                default: stats.todo += 1
                }
                stats.total += 1
            }
            stats.lead = summary.lead?.name
            stats.targetDate = summary.targetDate.flatMap(dayFormatter.date(from:))
            return .success((stats, summary.issues.nodes))
        } catch {
            return .failure(error)
        }
    }

    private static func loadSlack(_ p: Project, _ app: AppState) async -> Result<ProjectSnapshot.SlackStats?, Error> {
        guard let id = p.slack?.id else { return .success(nil) }
        do {
            let weekAgo = Date().addingTimeInterval(-7 * 86_400)
            var recent = try await app.withSlack { try await $0.history(id, limit: 200, since: weekAgo) }
            recent.removeAll { $0.subtype == "channel_join" || $0.subtype == "channel_leave" }
            var stats = ProjectSnapshot.SlackStats(messagesThisWeek: recent.count, lastActivity: recent.map(\.date).max())
            if stats.lastActivity == nil {
                stats.lastActivity = try await app.withSlack { try await $0.history(id, limit: 1) }.first?.date
            }
            return .success(stats)
        } catch {
            return .failure(error)
        }
    }

    private static func loadGitHub(_ p: Project, _ repos: Result<RepoCache, Error>, issues: [LinearClient.ProjectSummary.Issue]?)
        async -> Result<ProjectSnapshot.GitHubStats?, Error> {
        guard let repo = p.githubRepo else { return .success(nil) }
        do {
            let repos = try repos.get()
            let prs = ProjectPullRequests(pulls: try await repos.openPulls(repo), issues: issues,
                                          wholeRepository: p.showsWholeRepository)
            if prs.scoped, let issues {
                let pipeline = prs.pipeline(from: try await repos.runs(repo))
                let merged = ProjectPullRequests(pulls: try await repos.mergedPulls(repo), issues: issues, wholeRepository: false)
                let mergedIDs = Set(merged.matches.compactMap(\.issue))
                // Merged in code while the ticket still says "in progress" (review states are fine).
                let stale = issues.filter {
                    Delivery.isBehind(stateType: $0.state.type, stateName: $0.state.name, merged: mergedIDs.contains($0.identifier))
                }.map(\.identifier).sorted()
                return .success(.init(openPRs: prs.matches.count, pipeline: pipeline.state, scoped: true,
                                      mergedButOpen: stale,
                                      openPRIssues: Set(prs.matches.compactMap(\.issue)),
                                      mergedPRIssues: mergedIDs))
            }
            // Unscoped: the health of the default branch, not of whichever branch ran last.
            let branch = try await repos.defaultBranch(repo)
            let run = try await repos.runs(repo, branch: branch).first
            return .success(.init(openPRs: prs.matches.count,
                                  pipeline: run.map(ProjectSnapshot.PipelineState.init(run:)) ?? .unknown,
                                  branch: branch))
        } catch {
            return .failure(error)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Memoizes GitHub requests during one refresh, so projects sharing a repository
/// (a monorepo) fetch its pull requests and runs only once.
actor RepoCache {
    private let client: GitHubClient
    private var tasks: [String: Task<Any, Error>] = [:]

    init(client: GitHubClient) { self.client = client }

    private func value<T>(_ key: String, _ fetch: @escaping @Sendable () async throws -> T) async throws -> T {
        if let task = tasks[key] { return try await task.value as! T }
        let task = Task<Any, Error> { try await fetch() }
        tasks[key] = task
        return try await task.value as! T
    }

    func openPulls(_ repo: String) async throws -> [GitHubPull] {
        try await value("open:\(repo)") { [client] in try await client.pulls(repo) }
    }

    func mergedPulls(_ repo: String) async throws -> [GitHubPull] {
        try await value("merged:\(repo)") { [client] in try await client.mergedPulls(repo) }
    }

    func runs(_ repo: String, branch: String? = nil) async throws -> [GitHubRun] {
        try await value("runs:\(repo):\(branch ?? "*")") { [client] in try await client.runs(repo, branch: branch) }
    }

    func defaultBranch(_ repo: String) async throws -> String {
        try await value("branch:\(repo)") { [client] in try await client.defaultBranch(repo) }
    }
}

/// Plural-aware strings outside of SwiftUI `Text` (which inflects on its own).
enum Plural {
    static func text(_ key: String.LocalizationValue) -> String {
        String(AttributedString(localized: key).characters)
    }
}
