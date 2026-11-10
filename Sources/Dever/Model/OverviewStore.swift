import Foundation

/// Cross-service snapshot of one project, as shown on the overview.
struct ProjectSnapshot {
    struct LinearStats {
        var total = 0
        var done = 0
        var inProgress = 0
        var todo = 0
        var lead: String?
        /// The Linear team the project belongs to (the first, when it spans several).
        var team: String?
        var targetDate: Date?

        var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    struct SlackStats {
        var messagesThisWeek = 0
        var lastActivity: Date?
        /// Who wrote the channel's latest message, for "Léa in #channel".
        var lastAuthor: String?
        /// Messages from others since Slack's read cursor (which Dever moves when you read the
        /// channel here), over the last week; nil when the cursor could not be read.
        var unread: Int?
        /// The oldest of them, where reading starts, and when the newest arrived.
        var firstUnreadTS: String?
        var lastUnreadAt: Date?
        /// The unread messages that name you, newest first.
        var mentions: [Mention] = []

        struct Mention: Equatable {
            var ts: String
            var author: String
            var text: String
            var date: Date
        }
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
        /// The repositories these numbers add up, and those whose pipeline fails.
        var repositories: [String] = []
        var failingRepositories: [String] = []
        /// The project's open pull requests where your review is asked for.
        var reviewRequests: [ReviewRequest] = []
        /// The open pull request that has waited longest for a review, past three days.
        var longWait: (number: Int, since: Date)?
        /// The latest merged pull request: who wrote it, its number, when it landed.
        var lastMerged: (number: Int, author: String, date: Date)?

        struct ReviewRequest: Equatable {
            var number: Int
            var title: String
            var url: String
            /// The Linear issue the pull request belongs to, when it is matched to one.
            var issue: String?
            var date: Date
        }

        /// One project's numbers across its repositories: counts add up, sets join, the
        /// pipeline is the worst of them.
        static func combined(_ parts: [(repo: String, stats: GitHubStats)]) -> GitHubStats {
            guard parts.count > 1 else { return parts.first?.stats ?? GitHubStats() }
            var out = GitHubStats()
            for (repo, s) in parts {
                out.openPRs += s.openPRs
                out.scoped = out.scoped || s.scoped
                out.mergedButOpen += s.mergedButOpen
                out.openPRIssues.formUnion(s.openPRIssues)
                out.mergedPRIssues.formUnion(s.mergedPRIssues)
                out.repositories.append(repo)
                if s.pipeline == .failing { out.failingRepositories.append(repo) }
                out.reviewRequests += s.reviewRequests
                if let w = s.longWait, w.since < (out.longWait?.since ?? .distantFuture) { out.longWait = w }
                if let m = s.lastMerged, m.date > (out.lastMerged?.date ?? .distantPast) { out.lastMerged = m }
            }
            out.reviewRequests.sort { $0.date > $1.date }
            out.mergedButOpen = Array(Set(out.mergedButOpen)).sorted()
            out.pipeline = PipelineState.worst(parts.map(\.stats.pipeline))
            return out
        }
    }

    enum PipelineState {
        case passing, failing, running, unknown

        /// Failing wins, then running, then passing.
        static func worst(_ states: [PipelineState]) -> PipelineState {
            states.contains(.failing) ? .failing
            : states.contains(.running) ? .running
            : states.contains(.passing) ? .passing
            : .unknown
        }
    }

    var linear: LinearStats?
    var slack: SlackStats?
    var github: GitHubStats?
    /// Issues by delivery stage (Linear joined with GitHub); nil without Linear.
    var delivery: Delivery?
    /// The project shares the workspace repository and has no Linear issues to find its pull
    /// requests by: GitHub stays out of its row and its health.
    var githubNeedsLinear = false
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
    /// Number of days without Slack activity after which a project is "quiet"
    /// (Settings › Overview › Quiet after).
    static var quietAfterDays: Int { Preferences.quietAfterDays }

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

    /// Snapshots older than this are refreshed when the overview appears (Settings › Refresh every).
    static var staleAfter: TimeInterval { TimeInterval(Preferences.refreshMinutes) * 60 }

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
        // Snapshots: a made-up workspace instead of the linked one (Support/OverviewDemo.swift).
        if let demo = OverviewDemo.scene {
            if app.projects.map(\.id) != demo.projects.map(\.id) { app.projects = demo.projects }
            snapshots = demo.snapshots
            lastRefresh = Date()
            return
        }
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
        // On the shared repository only the pull requests of the project's issues are its own;
        // without issues to match (no Linear project, or Linear failed) GitHub is left out.
        let shared = await app.followsSharedRepository(p)
        let whole = await app.showsWholeRepository(p)
        let repositories = shared && issues == nil ? [] : await app.repositories(for: p)
        if shared && issues == nil, !(await app.repositories(for: p)).isEmpty { s.githubNeedsLinear = true }
        let login = await app.github?.login
        async let github = loadGitHub(p, repositories, repos, issues: projectIssues, whole: whole, login: login)
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
            stats.team = summary.teams?.nodes.first?.name
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
            var latest = recent.max { $0.ts < $1.ts }
            if latest == nil {
                latest = try await app.withSlack { try await $0.history(id, limit: 1) }.first
                stats.lastActivity = latest?.date
            }
            let me = await app.slack?.userID
            let team = await app.slack?.teamID ?? ""
            let users = (try? await app.withSlack { try await SlackDirectory.shared.users(team: team, via: $0) }) ?? [:]
            stats.lastAuthor = latest?.user.flatMap { users[$0]?.name }
            // What arrived since your last read, from others; mentions of you put forward.
            if let cursor = try? await app.withSlack({ try await $0.lastRead(id) }) {
                let unread = recent.filter { !SlackTS.isAtOrBefore($0.ts, cursor) && $0.user != me && $0.subtype == nil }
                stats.unread = unread.count
                stats.firstUnreadTS = unread.min { $0.ts < $1.ts }?.ts
                stats.lastUnreadAt = unread.map(\.date).max()
                if let me {
                    stats.mentions = unread.filter { ($0.text ?? "").contains("<@\(me)>") }
                        .sorted { $0.ts > $1.ts }
                        .map { m in
                            .init(ts: m.ts, author: m.user.flatMap { users[$0]?.name } ?? "Someone",
                                  text: SlackPlain.text(m.text ?? "", users: users), date: m.date)
                        }
                }
            }
            return .success(stats)
        } catch {
            return .failure(error)
        }
    }

    /// Every repository the project follows, added up; one failing call fails the whole.
    private static func loadGitHub(_ p: Project, _ repositories: [String], _ repos: Result<RepoCache, Error>,
                                   issues: [LinearClient.ProjectSummary.Issue]?, whole: Bool, login: String?)
        async -> Result<ProjectSnapshot.GitHubStats?, Error> {
        guard !repositories.isEmpty else { return .success(nil) }
        var parts: [(repo: String, stats: ProjectSnapshot.GitHubStats)] = []
        for repo in repositories {
            switch await loadGitHub(p, repo: repo, repos, issues: issues, whole: whole, login: login) {
            case .success(let stats): parts.append((repo, stats))
            case .failure(let error): return .failure(error)
            }
        }
        var combined = ProjectSnapshot.GitHubStats.combined(parts)
        combined.repositories = repositories
        if parts.count == 1, combined.pipeline == .failing { combined.failingRepositories = repositories }
        return .success(combined)
    }

    private static func loadGitHub(_ p: Project, repo: String, _ repos: Result<RepoCache, Error>,
                                   issues: [LinearClient.ProjectSummary.Issue]?, whole: Bool, login: String?)
        async -> Result<ProjectSnapshot.GitHubStats, Error> {
        do {
            let repos = try repos.get()
            let prs = ProjectPullRequests(pulls: try await repos.openPulls(repo), issues: issues,
                                          wholeRepository: whole)
            let attention = await Self.attention(prs, repo: repo, repos: repos, issues: issues, whole: whole,
                                                 login: login)
            if prs.scoped, let issues {
                let pipeline = prs.pipeline(from: try await repos.runs(repo))
                let merged = ProjectPullRequests(pulls: try await repos.mergedPulls(repo), issues: issues, wholeRepository: false)
                let mergedIDs = Set(merged.matches.compactMap(\.issue))
                // Merged in code while the ticket still says "in progress" (review states are fine).
                let stale = issues.filter {
                    Delivery.isBehind(stateType: $0.state.type, stateName: $0.state.name, merged: mergedIDs.contains($0.identifier))
                }.map(\.identifier).sorted()
                var stats = ProjectSnapshot.GitHubStats(openPRs: prs.matches.count, pipeline: pipeline.state, scoped: true,
                                                        mergedButOpen: stale,
                                                        openPRIssues: Set(prs.matches.compactMap(\.issue)),
                                                        mergedPRIssues: mergedIDs)
                attention.apply(to: &stats)
                return .success(stats)
            }
            // Unscoped: the health of the default branch, not of whichever branch ran last.
            let branch = try await repos.defaultBranch(repo)
            let run = try await repos.runs(repo, branch: branch).first
            var stats = ProjectSnapshot.GitHubStats(openPRs: prs.matches.count,
                                                    pipeline: run.map(ProjectSnapshot.PipelineState.init(run:)) ?? .unknown,
                                                    branch: branch)
            attention.apply(to: &stats)
            return .success(stats)
        } catch {
            return .failure(error)
        }
    }

    /// What in one repository waits for you or holds the project back: the pull requests whose
    /// review is asked of you, the one waiting longest, and the latest merge.
    private struct Attention {
        var reviews: [ProjectSnapshot.GitHubStats.ReviewRequest] = []
        var longWait: (number: Int, since: Date)?
        var lastMerged: (number: Int, author: String, date: Date)?

        func apply(to stats: inout ProjectSnapshot.GitHubStats) {
            stats.reviewRequests = reviews
            stats.longWait = longWait
            stats.lastMerged = lastMerged
        }
    }

    private static func attention(_ prs: ProjectPullRequests, repo: String, repos: RepoCache,
                                  issues: [LinearClient.ProjectSummary.Issue]?, whole: Bool, login: String?) async -> Attention {
        var out = Attention()
        let me = login?.lowercased()
        for m in prs.matches {
            let pull = m.pull
            let updated = Self.iso(pull.updated_at) ?? Date()
            let reviewers = pull.requested_reviewers ?? []
            if let me, reviewers.contains(where: { $0.login.lowercased() == me }) {
                out.reviews.append(.init(number: pull.number, title: pull.title, url: pull.html_url, issue: m.issue, date: updated))
            }
            if pull.draft != true, !reviewers.isEmpty, Date().timeIntervalSince(updated) > 3 * 86_400,
               updated < (out.longWait?.since ?? .distantFuture) {
                out.longWait = (pull.number, updated)
            }
        }
        // The merges of this project only (the same matching as the open ones).
        if let merged = try? await repos.mergedPulls(repo) {
            let mine = ProjectPullRequests(pulls: merged, issues: issues, wholeRepository: whole).matches
            if let last = mine.compactMap({ m in m.pull.merged_at.flatMap(Self.iso).map { (m.pull, $0) } }).max(by: { $0.1 < $1.1 }) {
                out.lastMerged = (last.0.number, last.0.user.login, last.1)
            }
        }
        return out
    }

    private static func iso(_ s: String) -> Date? { ISO8601DateFormatter().date(from: s) }

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
