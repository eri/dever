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
        var lastRun: GitHubRun?

        var pipeline: PipelineState {
            guard let run = lastRun else { return .unknown }
            if run.status != "completed" { return .running }
            return run.conclusion == "success" ? .passing : .failing
        }
    }

    enum PipelineState { case passing, failing, running, unknown }

    var linear: LinearStats?
    var slack: SlackStats?
    var github: GitHubStats?
    var errors: [ServiceKind: String] = [:]
    var updatedAt = Date()
}

/// Overall state of a project, derived from its links and its snapshot.
enum ProjectStatus: Int, Comparable {
    case needsAttention, incomplete, quiet, onTrack, loading

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .needsAttention: "Needs attention"
        case .incomplete: "Incomplete"
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
        out += s.errors.keys.sorted { $0.rawValue < $1.rawValue }.map { "Couldn't load \($0.label) data" }
        return out
    }

    func status(_ s: ProjectSnapshot?) -> ProjectStatus {
        guard let s else { return isComplete ? .loading : .incomplete }
        if s.github?.pipeline == .failing { return .needsAttention }
        if let target = s.linear?.targetDate, target < Calendar.current.startOfDay(for: Date()),
           let l = s.linear, l.done < l.total {
            return .needsAttention
        }
        if !isComplete { return .incomplete }
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

    func refresh(_ app: AppState) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = Date() }

        let projects = app.projects
        // A few projects at a time keeps us well under the Slack/GitHub rate limits.
        await withTaskGroup(of: (UUID, ProjectSnapshot).self) { group in
            var pending = projects.makeIterator()
            for _ in 0..<4 {
                guard let p = pending.next() else { break }
                group.addTask { await (p.id, Self.load(p, app)) }
            }
            for await (id, snapshot) in group {
                snapshots[id] = snapshot
                if let p = pending.next() { group.addTask { await (p.id, Self.load(p, app)) } }
            }
        }
        let ids = Set(projects.map(\.id))
        snapshots = snapshots.filter { ids.contains($0.key) }
    }

    private static func load(_ p: Project, _ app: AppState) async -> ProjectSnapshot {
        var s = ProjectSnapshot()
        async let linear = loadLinear(p, app)
        async let slack = loadSlack(p, app)
        async let github = loadGitHub(p, app)
        switch await linear {
        case .success(let v): s.linear = v
        case .failure(let e): s.errors[.linear] = e.localizedDescription
        }
        switch await slack {
        case .success(let v): s.slack = v
        case .failure(let e): s.errors[.slack] = e.localizedDescription
        }
        switch await github {
        case .success(let v): s.github = v
        case .failure(let e): s.errors[.github] = e.localizedDescription
        }
        return s
    }

    private static func loadLinear(_ p: Project, _ app: AppState) async -> Result<ProjectSnapshot.LinearStats?, Error> {
        guard let id = p.linear?.id, app.linear != nil else { return .success(nil) }
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
            return .success(stats)
        } catch {
            return .failure(error)
        }
    }

    private static func loadSlack(_ p: Project, _ app: AppState) async -> Result<ProjectSnapshot.SlackStats?, Error> {
        guard let id = p.slack?.id, app.slack != nil else { return .success(nil) }
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

    private static func loadGitHub(_ p: Project, _ app: AppState) async -> Result<ProjectSnapshot.GitHubStats?, Error> {
        guard let repo = p.githubRepo, app.github != nil else { return .success(nil) }
        do {
            let client = try app.githubClient()
            // The card shows the health of the default branch, not of whichever branch ran last.
            async let pulls = client.pulls(repo)
            let branch = try await client.defaultBranch(repo)
            let runs = try await client.runs(repo, branch: branch)
            return .success(ProjectSnapshot.GitHubStats(openPRs: try await pulls.count, lastRun: runs.first))
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
