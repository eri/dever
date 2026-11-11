import Combine
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
        /// Every unread message's `ts`, so reading part of the channel can be subtracted.
        var unreadTS: [String] = []
        /// More unread messages than one call brings (200): the count is shown as "200+".
        var unreadCapped = false

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
    /// When the last refresh that reached the tools ended. A cycle in which every call failed
    /// does not count: the rows are as old as this says.
    @Published private(set) var lastRefresh: Date?
    /// The latest cycle reached nothing (offline, or every service failing).
    @Published private(set) var refreshFailed = false
    private var lastAttempt: Date?
    private var failures = 0

    /// Snapshots older than this are refreshed when the overview appears (Settings › Refresh every).
    static var staleAfter: TimeInterval { TimeInterval(Preferences.refreshMinutes) * 60 }

    /// Due for a refresh. After a failed cycle the next try comes sooner than the setting:
    /// 30 s, then twice as long each time, up to the setting.
    var isStale: Bool {
        if refreshFailed, let lastAttempt {
            let wait = min(Self.staleAfter, 30 * pow(2, Double(max(0, failures - 1))))
            return Date().timeIntervalSince(lastAttempt) > wait
        }
        return lastRefresh.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? true
    }

    private var autoRefresh: Task<Void, Never>?
    private weak var app: AppState?
    private var following: AnyCancellable?

    /// Keeps snapshots fresh (and notifications flowing) for as long as the app runs,
    /// even with its window closed.
    func startAutoRefresh(_ app: AppState) {
        guard autoRefresh == nil else { return }
        self.app = app
        // Between two cycles the rows follow the stores: an issue moved in Delivery, a
        // repository a project page read again. Changes that come together count once.
        following = IssueStore.shared.$projects.map { _ in () }
            .merge(with: GitHubStore.shared.$revision.map { _ in () })
            .dropFirst(2)
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] in self?.rederive() }
        autoRefresh = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isStale { await self.refresh(app) }
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    /// Works each row's Linear and GitHub parts out again from what the stores hold, without
    /// a request. A row whose tool is failing, or whose data the stores do not hold, is left.
    func rederive() {
        guard let app, !isRefreshing, OverviewDemo.scene == nil else { return }
        let login = app.github?.login
        for p in app.projects {
            guard var s = snapshots[p.id], s.errors[.linear] == nil, s.errors[.github] == nil else { continue }
            let issues = p.linear.flatMap { IssueStore.shared.projects[$0.id]?.issues }
            if p.linear != nil, issues == nil { continue }
            if let issues { s.linear?.count(issues) }
            let repositories = app.repositories(for: p)
            if s.github != nil, !repositories.isEmpty {
                let held = repositories.compactMap { name in GitHubStore.shared.repository(name).map { (name: name, data: $0) } }
                if held.count == repositories.count {
                    s.github = .project(repositories: held, issues: issues, wholeRepository: app.showsWholeRepository(p), login: login)
                }
            }
            if let issues, s.linear != nil { s.delivery = Delivery(issues: issues, github: s.github) }
            snapshots[p.id] = s
        }
    }

    /// The channel was read up to `ts` in Dever: what came before it leaves the project's
    /// "for you" at once, without reloading anything.
    func slackRead(_ project: UUID, upTo ts: String) {
        guard var s = snapshots[project]?.slack else { return }
        s.mentions.removeAll { SlackTS.isAtOrBefore($0.ts, ts) }
        s.unreadTS.removeAll { SlackTS.isAtOrBefore($0, ts) }
        if s.unread != nil { s.unread = s.unreadTS.count }
        s.firstUnreadTS = s.unreadTS.min { (Double($0) ?? 0) < (Double($1) ?? 0) }
        if s.unreadTS.isEmpty { s.lastUnreadAt = nil; s.unreadCapped = false }
        snapshots[project]?.slack = s
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
        defer { isRefreshing = false }

        let projects = app.projects
        let repos = Result { RepoCache(client: try app.githubClient()) }
        let known = snapshots
        var reached = !projects.contains { $0.slack != nil || $0.linear != nil || !app.repositories(for: $0).isEmpty }
        // A project's Slack part is shown as soon as it arrives: a mention does not wait for GitHub.
        let early: @Sendable (UUID, ProjectSnapshot.SlackStats) async -> Void = { [weak self] id, slack in
            await self?.publish(slack, for: id)
        }
        // A few projects at a time keeps us well under the Slack/GitHub rate limits.
        await withTaskGroup(of: (UUID, ProjectSnapshot).self) { group in
            var pending = projects.makeIterator()
            func add(_ p: Project) {
                let previous = known[p.id]
                group.addTask { await (p.id, Self.load(p, app, repos, previous: previous, early: early)) }
            }
            for _ in 0..<4 {
                guard let p = pending.next() else { break }
                add(p)
            }
            for await (id, snapshot) in group {
                snapshots[id] = snapshot
                // Reached: some tool the project links answered.
                let linked = (projects.first { $0.id == id }).map { p in
                    (p.slack != nil ? 1 : 0) + (p.linear != nil ? 1 : 0) + (app.repositories(for: p).isEmpty ? 0 : 1)
                } ?? 0
                if snapshot.errors.values.filter(\.isTransient).count < linked { reached = true }
                if let p = pending.next() { add(p) }
            }
        }
        lastAttempt = Date()
        if reached {
            lastRefresh = Date(); refreshFailed = false; failures = 0
        } else {
            refreshFailed = true; failures += 1
        }
        let ids = Set(projects.map(\.id))
        snapshots = snapshots.filter { ids.contains($0.key) }
        Notifier.shared.process(projects: projects, snapshots: snapshots)
        // Previews ride the same cycle, after the snapshots so the rows fill in first.
        await PreviewStore.shared.refreshAll(projects, app: app)
    }

    /// A refresh in flight got the project's Slack part: the row takes it without waiting for the rest.
    private func publish(_ slack: ProjectSnapshot.SlackStats, for project: UUID) {
        guard snapshots[project] != nil else { return }
        snapshots[project]?.slack = slack
    }

    /// - Parameter previous: the project's last snapshot. What a service that cannot be reached
    ///   right now (offline, a 5xx) showed stays, beside the error that says it is old.
    private static func load(_ p: Project, _ app: AppState, _ repos: Result<RepoCache, Error>, previous: ProjectSnapshot?,
                             early: @escaping @Sendable (UUID, ProjectSnapshot.SlackStats) async -> Void) async -> ProjectSnapshot {
        var s = ProjectSnapshot()
        async let slack: Result<ProjectSnapshot.SlackStats?, Error> = {
            let result = await loadSlack(p, app)
            if case .success(let stats?) = result { await early(p.id, stats) }
            return result
        }()
        // GitHub waits for Linear: the project's issues decide which PRs belong to it.
        var issues: [LinearIssue]?
        switch await loadLinear(p, app, previous: previous?.linear) {
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
        if let previous {
            if s.errors[.slack]?.isTransient == true { s.slack = previous.slack }
            if s.errors[.linear]?.isTransient == true { s.linear = previous.linear }
            if s.errors[.github]?.isTransient == true || (s.errors[.linear]?.isTransient == true && s.github == nil) {
                s.github = previous.github
            }
            if s.errors.values.contains(where: \.isTransient) { s.updatedAt = previous.updatedAt }
        }
        if let issues {
            s.delivery = Delivery(issues: issues, github: s.github)
        } else if s.errors[.linear]?.isTransient == true {
            s.delivery = previous?.delivery
        }
        return s
    }

    /// The project's issues, from the list every screen shares (a delta after the first
    /// load), and its own facts. The facts are not worth failing the row for: when they
    /// cannot be read the previous ones stay.
    private static func loadLinear(_ p: Project, _ app: AppState, previous: ProjectSnapshot.LinearStats?)
        async -> Result<(stats: ProjectSnapshot.LinearStats, issues: [LinearIssue])?, Error> {
        guard let id = p.linear?.id else { return .success(nil) }
        do {
            async let facts = try? IssueStore.shared.facts(project: id, app: app)
            let issues = try await IssueStore.shared.load(project: id, maxAge: RepoCache.maxAge, app: app)
            let known = await facts ?? previous.map { LinearProjectFacts(lead: $0.lead, team: $0.team, targetDate: $0.targetDate) }
            return .success((ProjectSnapshot.LinearStats(issues: issues, facts: known), issues))
        } catch {
            return .failure(error)
        }
    }

    private static func loadSlack(_ p: Project, _ app: AppState) async -> Result<ProjectSnapshot.SlackStats?, Error> {
        guard let id = p.slack?.id else { return .success(nil) }
        do {
            let weekAgo = Date().addingTimeInterval(-7 * 86_400)
            let team = await app.slack?.teamID ?? ""
            let users = (try? await app.withSlack { try await SlackDirectory.shared.users(team: team, via: $0) }) ?? [:]
            // People only: joins, renames, pins, topics and what apps and bots post are not
            // something a person said, so they neither count nor make "the last activity".
            func spoken(_ m: SlackMessage) -> Bool {
                guard [nil, "thread_broadcast", "file_share"].contains(m.subtype), let user = m.user else { return false }
                return users[user]?.isBot != true
            }
            var recent = try await app.withSlack { try await $0.history(id, limit: 200, since: weekAgo) }
            recent.removeAll { !spoken($0) }
            var stats = ProjectSnapshot.SlackStats(messagesThisWeek: recent.count, lastActivity: recent.map(\.date).max())
            var latest = recent.max { $0.ts < $1.ts }
            if latest == nil {
                latest = try await app.withSlack { try await $0.history(id, limit: 20) }.filter(spoken).max { $0.ts < $1.ts }
                stats.lastActivity = latest?.date
            }
            let me = await app.slack?.userID
            stats.lastAuthor = latest?.user.flatMap { users[$0]?.name }
            // What arrived since your last read, from others; mentions of you put forward.
            // Everything since your read position, however old: one call from the cursor on.
            if let cursor = try? await app.withSlack({ try await $0.lastRead(id) }),
               let page = try? await app.withSlack({ try await $0.historyAfter(id, ts: cursor) }) {
                let unread = page.messages.filter { spoken($0) && $0.user != me && !SlackTS.isAtOrBefore($0.ts, cursor) }
                stats.unread = unread.count
                stats.unreadCapped = page.hasMore
                stats.unreadTS = unread.map(\.ts)
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

    /// Every repository the project follows, read through the store and added up; one
    /// failing read fails the whole.
    private static func loadGitHub(_ p: Project, _ repositories: [String], _ repos: Result<RepoCache, Error>,
                                   issues: [LinearIssue]?, whole: Bool, login: String?)
        async -> Result<ProjectSnapshot.GitHubStats?, Error> {
        guard !repositories.isEmpty else { return .success(nil) }
        do {
            let repos = try repos.get()
            var held: [(name: String, data: GitHubStore.Repository)] = []
            for repo in repositories { held.append((repo, try await repos.repository(repo))) }
            return .success(.project(repositories: held, issues: issues, wholeRepository: whole, login: login))
        } catch {
            return .failure(error)
        }
    }
}

/// Reads repositories through `GitHubStore` during one refresh: projects sharing a repository
/// (a monorepo) read it once, and a repository a project page read a moment ago is not asked again.
struct RepoCache {
    let client: GitHubClient
    /// A cycle takes what was read within this long, by itself or by a project page.
    static let maxAge: TimeInterval = 20

    func repository(_ repo: String) async throws -> GitHubStore.Repository {
        try await GitHubStore.shared.load(repo, client: client, maxAge: Self.maxAge)
    }
}

/// Plural-aware strings outside of SwiftUI `Text` (which inflects on its own).
enum Plural {
    static func text(_ key: String.LocalizationValue) -> String {
        String(AttributedString(localized: key).characters)
    }
}
