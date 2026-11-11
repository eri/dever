import AppKit
import Foundation

/// Where the team's code stands between staging and production, for the Overview's release
/// line: the last pull request merged into staging (staging deploys on merge) with the checks
/// of its head, the last one merged into production, and the release pull request waiting to
/// go there. Read for one repository: the workspace's, or the one most projects follow.
///
/// Data contract (docs/data-freshness.md):
/// - Reads: one GraphQL query per refresh (about 2 kB): the two branches' last merges, the
///   open release pull request, the checks of the staging head and of that pull request.
/// - Writes: nothing. Invalidates: nothing.
/// - Budget: 2 minutes; refreshed by the Overview's own cycle, never more often.
/// - Loading: a skeleton line until the first answer; a refresh keeps the line as it is.
/// - Failure: the last line stays, with how old it is.
/// - Exits: each part opens its pull request on GitHub; coming back reads the line again.
@MainActor
final class ReleaseStore: ObservableObject {
    static let shared = ReleaseStore()

    struct Merge: Equatable {
        var number: Int
        var title: String
        var author: String
        var date: Date
        var url: URL
    }

    struct Release: Equatable {
        var number: Int
        var title: String = ""
        var author: String
        var opened: Date
        var url: URL
        var checks: ProjectSnapshot.PipelineState
        var checkList: [Check] = []
    }

    /// One check of a commit: a workflow job or a commit status, its state, where to read it.
    struct Check: Equatable, Identifiable {
        var name: String
        var state: ProjectSnapshot.PipelineState
        var url: URL?
        var id: String { name }
    }

    struct State: Equatable {
        var repository: String
        var stagingBranch: String?
        var productionBranch: String
        var staging: Merge?
        var stagingChecks: ProjectSnapshot.PipelineState = .unknown
        var stagingCheckList: [Check] = []
        var production: Merge?
        var next: Release?
        /// When staging last went to production: the merge of the last release pull request
        /// (staging into production). Nil when there is no staging branch: merges go straight out.
        var lastRelease: Date?

        /// Where a pull request merged at `date` is now: on staging until a release took it.
        func environment(mergedAt date: Date) -> Environment {
            guard stagingBranch != nil else { return .production }
            guard let lastRelease else { return .staging }
            return date <= lastRelease ? .production : .staging
        }
    }

    enum Environment { case staging, production }

    @Published private(set) var state: State?
    /// When the last answer arrived; with `failed`, how old the line is.
    @Published private(set) var loadedAt: Date?
    @Published private(set) var failed = false
    /// A part was opened on GitHub: read again when Dever comes back to the front.
    private var dirty = false
    private var loading = false
    static let budget: TimeInterval = 120

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                let store = ReleaseStore.shared
                guard store.dirty, let app = store.app else { return }
                store.dirty = false
                await store.refresh(app, force: true)
            }
        }
    }

    private weak var app: AppState?

    /// The repository the line speaks for: the workspace's, else the one most projects follow.
    static func repository(_ app: AppState) -> String? {
        if let shared = app.workspaceRepository, app.repositoryMode.usesWorkspaceRepository { return shared }
        let counts = Dictionary(app.projects.flatMap { app.repositories(for: $0) }.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
    }

    func opened() { dirty = true }

    func refresh(_ app: AppState, force: Bool = false) async {
        self.app = app
        if let demo = OverviewDemo.release { state = demo; loadedAt = Date(); return }
        guard let repository = Self.repository(app), app.github != nil else { state = nil; return }
        if !force, state?.repository == repository, let loadedAt, !failed,
           Date().timeIntervalSince(loadedAt) < Self.budget { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let next = try await Self.load(repository, client: try app.githubClient())
            state = next
            loadedAt = Date()
            failed = false
        } catch {
            if state?.repository != repository { state = nil }
            failed = true
        }
    }

    // MARK: Loading

    private struct Answer: Decodable {
        struct Repo: Decodable {
            struct BranchRef: Decodable { var name: String }
            struct Rollup: Decodable {
                var state: String
                struct Context: Decodable {
                    var __typename: String
                    var name: String?
                    var conclusion: String?
                    var status: String?
                    var detailsUrl: String?
                    var context: String?
                    var state: String?
                    var targetUrl: String?
                }
                struct Contexts: Decodable { var nodes: [Context] }
                var contexts: Contexts?
            }
            struct Target: Decodable { var statusCheckRollup: Rollup? }
            struct Head: Decodable { var target: Target? }
            struct Author: Decodable { var login: String }
            struct PR: Decodable {
                var number: Int
                var title: String
                var url: String
                var mergedAt: String?
                var createdAt: String
                var headRefName: String?
                var author: Author?
                struct Commits: Decodable {
                    struct Node: Decodable { struct C: Decodable { var statusCheckRollup: Rollup? }; var commit: C }
                    var nodes: [Node]
                }
                var commits: Commits?
            }
            struct PRs: Decodable { var nodes: [PR] }
            var defaultBranchRef: BranchRef?
            var main: Head?
            var master: Head?
            var stagingRef: Head?
            var mergedMain: PRs
            var mergedMaster: PRs
            var openMain: PRs
            var openMaster: PRs
            var mergedDefault: PRs?
        }
        var repository: Repo?
    }

    private static func load(_ repository: String, client: GitHubClient) async throws -> State {
        let parts = repository.split(separator: "/").map(String.init)
        guard parts.count == 2 else { throw AppError.message("Not a repository: \(repository)") }
        // Production is `main` (or `master`); staging is the default branch when it is not one
        // of them, else a branch named `staging`.
        let prFields = "number title url mergedAt createdAt headRefName author { login }"
        let query = """
        query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) {
          defaultBranchRef { name }
          main: ref(qualifiedName: "refs/heads/main") { target { ... on Commit { statusCheckRollup { state } } } }
          master: ref(qualifiedName: "refs/heads/master") { target { ... on Commit { statusCheckRollup { state } } } }
          stagingRef: ref(qualifiedName: "refs/heads/staging") { target { ... on Commit { statusCheckRollup { state } } } }
          mergedMain: pullRequests(baseRefName: "main", states: MERGED, first: 6, orderBy: { field: UPDATED_AT, direction: DESC }) { nodes { \(prFields) } }
          mergedMaster: pullRequests(baseRefName: "master", states: MERGED, first: 6, orderBy: { field: UPDATED_AT, direction: DESC }) { nodes { \(prFields) } }
          openMain: pullRequests(baseRefName: "main", states: OPEN, first: 1, orderBy: { field: CREATED_AT, direction: DESC }) { nodes { \(prFields) commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 40) { nodes { __typename ... on CheckRun { name conclusion status detailsUrl } ... on StatusContext { context state targetUrl } } } } } } } } }
          openMaster: pullRequests(baseRefName: "master", states: OPEN, first: 1, orderBy: { field: CREATED_AT, direction: DESC }) { nodes { \(prFields) commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 40) { nodes { __typename ... on CheckRun { name conclusion status detailsUrl } ... on StatusContext { context state targetUrl } } } } } } } } }
        } }
        """
        let answer = try await client.graphql(query, variables: ["owner": parts[0], "name": parts[1]], as: Answer.self)
        guard let repo = answer.repository else { throw AppError.message("No access to \(repository)") }
        let production = repo.main != nil || repo.master == nil ? "main" : "master"
        let defaultBranch = repo.defaultBranchRef?.name
        let staging: String? = defaultBranch.flatMap { ["main", "master"].contains($0) ? nil : $0 } ?? (repo.stagingRef != nil ? "staging" : nil)

        var state = State(repository: repository, stagingBranch: staging, productionBranch: production)
        let merged = production == "main" ? repo.mergedMain : repo.mergedMaster
        state.production = latest(merged.nodes)
        if let staging {
            state.lastRelease = merged.nodes.filter { $0.headRefName == staging }.compactMap { $0.mergedAt.flatMap(iso) }.max()
        }
        if let open = (production == "main" ? repo.openMain : repo.openMaster).nodes.first, let url = URL(string: open.url) {
            let r = open.commits?.nodes.last?.commit.statusCheckRollup
            state.next = Release(number: open.number, title: open.title, author: open.author?.login ?? "someone",
                                 opened: iso(open.createdAt) ?? Date(), url: url,
                                 checks: rollup(r), checkList: checks(r))
        }
        if let staging {
            // The staging branch's own merges: one more small query, only when it exists.
            let q = """
            query($owner: String!, $name: String!, $base: String!) { repository(owner: $owner, name: $name) {
              pullRequests(baseRefName: $base, states: MERGED, first: 6, orderBy: { field: UPDATED_AT, direction: DESC }) { nodes { \(prFields) } }
              ref(qualifiedName: $base) { target { ... on Commit { statusCheckRollup { state contexts(first: 40) { nodes { __typename ... on CheckRun { name conclusion status detailsUrl } ... on StatusContext { context state targetUrl } } } } } } }
            } }
            """
            struct StagingAnswer: Decodable {
                struct R: Decodable { var pullRequests: Answer.Repo.PRs; var ref: Answer.Repo.Head? }
                var repository: R?
            }
            let s = try await client.graphql(q, variables: ["owner": parts[0], "name": parts[1], "base": staging], as: StagingAnswer.self)
            state.staging = latest(s.repository?.pullRequests.nodes ?? [])
            state.stagingChecks = rollup(s.repository?.ref?.target?.statusCheckRollup)
            state.stagingCheckList = checks(s.repository?.ref?.target?.statusCheckRollup)
        }
        return state
    }

    private static func latest(_ nodes: [Answer.Repo.PR]) -> Merge? {
        nodes.compactMap { pr -> Merge? in
            guard let at = pr.mergedAt.flatMap(iso), let url = URL(string: pr.url) else { return nil }
            return Merge(number: pr.number, title: pr.title, author: pr.author?.login ?? "someone", date: at, url: url)
        }
        .max { $0.date < $1.date }
    }

    private static func rollup(_ r: Answer.Repo.Rollup?) -> ProjectSnapshot.PipelineState {
        switch r?.state {
        case "SUCCESS": .passing
        case "FAILURE", "ERROR": .failing
        case "PENDING", "EXPECTED": .running
        default: .unknown
        }
    }

    /// Every check of a commit, failing first, then running, then passing.
    private static func checks(_ r: Answer.Repo.Rollup?) -> [Check] {
        let all: [Check] = (r?.contexts?.nodes ?? []).compactMap { c in
            if c.__typename == "CheckRun", let name = c.name {
                let state: ProjectSnapshot.PipelineState = switch c.conclusion {
                case "FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE": .failing
                case "SUCCESS", "NEUTRAL", "SKIPPED": .passing
                default: c.status == "COMPLETED" ? .unknown : .running
                }
                return Check(name: name, state: state, url: c.detailsUrl.flatMap(URL.init(string:)))
            }
            if let name = c.context {
                let state: ProjectSnapshot.PipelineState = switch c.state {
                case "FAILURE", "ERROR": .failing
                case "SUCCESS": .passing
                default: .running
                }
                return Check(name: name, state: state, url: c.targetUrl.flatMap(URL.init(string:)))
            }
            return nil
        }
        let rank: (ProjectSnapshot.PipelineState) -> Int = { [.failing: 0, .running: 1, .passing: 2][$0] ?? 3 }
        return all.sorted { rank($0.state) == rank($1.state) ? $0.name < $1.name : rank($0.state) < rank($1.state) }
    }

    private static func iso(_ s: String) -> Date? { ISO8601DateFormatter().date(from: s) }
}
