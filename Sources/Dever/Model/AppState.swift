import Foundation
import SwiftUI

enum ServiceKind: String, CaseIterable, Identifiable, Codable {
    case slack, linear, github
    var id: String { rawValue }
    var label: String {
        switch self {
        case .slack: "Slack"
        case .linear: "Linear"
        case .github: "GitHub"
        }
    }
    var symbol: String {
        switch self {
        case .slack: "number"
        case .linear: "checklist"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum AppError: LocalizedError {
    case message(String)
    case unauthorized(ServiceKind)
    case notConnected(ServiceKind)
    /// The service asked for fewer requests: nothing is sent to it for `retryAfter` seconds.
    case rateLimited(ServiceKind, retryAfter: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .message(let m): m
        case .rateLimited(let s, let wait):
            "\(s.label) asked Dever to slow down. Trying again in \(Int(wait.rounded(.up))) s."
        case .unauthorized(let s): "\(s.label): session expired, please reconnect the account."
        case .notConnected(let s): "\(s.label) is not connected."
        }
    }
}

/// Why a panel or a column has no data. Kept as a type, not a message, so the screen can
/// tell a tool that was never connected from one that is failing.
enum ServiceState: Equatable {
    /// No token: the user never connected the tool (or disconnected it). An invitation, not an error.
    case notConnected
    /// There is a token but the service rejects it: the session expired or was revoked.
    case unauthorized
    /// No network.
    case offline
    /// Anything else: a 5xx, a rate limit, a decoding error. The message is the service's own.
    case failed(String)

    init(_ error: Error) {
        switch error {
        case AppError.notConnected: self = .notConnected
        case AppError.unauthorized: self = .unauthorized
        case let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                                      .cannotFindHost, .cannotConnectToHost, .internationalRoamingOff].contains(e.code):
            self = .offline
        default: self = .failed(error.localizedDescription)
        }
    }

    /// True for the states that are the connection's fault, not the network's or the service's.
    var needsConnecting: Bool { self == .notConnected || self == .unauthorized }

    /// True for the states a retry may clear: what was loaded before is old, not gone.
    var isTransient: Bool { !needsConnecting }
}

/// How a team keeps its code: one repository for every project, one or several per project,
/// or both. Persisted with the rest of the settings.
enum RepositoryMode: String, CaseIterable, Identifiable, Codable {
    /// One repository for the whole workspace: every project follows it.
    case single
    /// Each project links one or several repositories of its own.
    case perProject
    /// A project follows the workspace repository, or its own list.
    case mixed

    var id: String { rawValue }
    static let key = "repositoryMode"
    static let workspaceKey = "workspaceRepository"

    var title: String {
        switch self {
        case .single: "One repository"
        case .perProject: "Repositories per project"
        case .mixed: "Both"
        }
    }

    var detail: String {
        switch self {
        case .single: "Every project follows the same repository"
        case .perProject: "Each project links one or more"
        case .mixed: "Some share one, some have their own"
        }
    }

    /// What a developer calls it, shown quietly beside the plain title.
    var term: String {
        switch self {
        case .single: "Monorepo"
        case .perProject: "Multi-repo"
        case .mixed: "Hybrid"
        }
    }

    var symbol: String {
        switch self {
        case .single: "square"
        case .perProject: "square.grid.2x2"
        case .mixed: "square.on.square"
        }
    }

    /// Whether the mode needs a workspace repository.
    var usesWorkspaceRepository: Bool { self != .perProject }
}

struct Project: Codable, Identifiable, Hashable {
    struct SlackLink: Codable, Hashable { var id: String; var name: String }
    struct LinearLink: Codable, Hashable { var id: String; var name: String; var url: String }

    var id = UUID()
    var name: String
    var slack: SlackLink?
    var linear: LinearLink?
    /// The project's own repositories (`owner/name`). What the project follows also depends on the
    /// workspace's `RepositoryMode`: see `AppState.repositories(for:)`.
    var githubRepos: [String] = []
    /// Mixed mode: true when the project follows the workspace repository rather than its own list.
    /// Nil means "the workspace repository unless it has repositories of its own".
    var usesWorkspaceRepository: Bool?
    /// nil/false: only PRs linked to the project's Linear issues (shared repositories).
    var githubWholeRepo: Bool?
    /// The pull request whose preview environment this project follows, and the repository it
    /// lives in (nil: the project's first repository, from before projects had several).
    var previewPullNumber: Int?
    var previewRepository: String?
    /// True once the user said this project needs no preview: the panel stays away until a
    /// pull request is picked in the editor.
    var previewDismissed: Bool?
    /// Pinned to the top of the Overview.
    var favorite: Bool?
    var createdAt = Date()

    init(id: UUID = UUID(), name: String, slack: SlackLink? = nil, linear: LinearLink? = nil,
         githubRepos: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.slack = slack
        self.linear = linear
        self.githubRepos = githubRepos
        self.createdAt = createdAt
    }

    /// Whether to show every PR of the repository rather than those of the project's issues.
    var showsWholeRepository: Bool { githubWholeRepo == true || linear == nil }

    /// A project is trackable once both Slack and Linear are linked.
    var isComplete: Bool { slack != nil && linear != nil }

    /// The repositories the project follows under a mode and a workspace repository.
    func repositories(mode: RepositoryMode, workspace: String?) -> [String] {
        let shared = workspace.map { [$0] } ?? []
        switch mode {
        case .single: return shared
        case .perProject: return githubRepos
        case .mixed: return (usesWorkspaceRepository ?? githubRepos.isEmpty) ? shared : githubRepos
        }
    }

    // MARK: Codable (projects saved before repository modes had one `githubRepo`)

    private enum CodingKeys: String, CodingKey {
        case id, name, slack, linear, githubRepos, usesWorkspaceRepository, githubWholeRepo
        case previewPullNumber, previewRepository, previewDismissed, favorite, createdAt
    }
    private enum LegacyKeys: String, CodingKey { case githubRepo }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        slack = try c.decodeIfPresent(SlackLink.self, forKey: .slack)
        linear = try c.decodeIfPresent(LinearLink.self, forKey: .linear)
        if let list = try c.decodeIfPresent([String].self, forKey: .githubRepos) {
            githubRepos = list
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            githubRepos = try legacy.decodeIfPresent(String.self, forKey: .githubRepo).map { [$0] } ?? []
        }
        usesWorkspaceRepository = try c.decodeIfPresent(Bool.self, forKey: .usesWorkspaceRepository)
        githubWholeRepo = try c.decodeIfPresent(Bool.self, forKey: .githubWholeRepo)
        previewPullNumber = try c.decodeIfPresent(Int.self, forKey: .previewPullNumber)
        previewRepository = try c.decodeIfPresent(String.self, forKey: .previewRepository)
        previewDismissed = try c.decodeIfPresent(Bool.self, forKey: .previewDismissed)
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// Slack channel naming convention: `<prefix><slug>`.
enum Naming {
    static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let mapped = folded.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(mapped).split(separator: "-").joined(separator: "-").prefix(80).description
    }

    static func channelName(for project: String, prefix: String) -> String {
        String((prefix + slug(project)).prefix(80))
    }

    /// Readable project name from a channel: `proj-acme-corp` → `Acme Corp`.
    static func projectName(fromChannel channel: String, prefix: String) -> String {
        var base = channel
        if !prefix.isEmpty, base.hasPrefix(prefix) { base.removeFirst(prefix.count) }
        return base.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The prefix most channels share (text up to and including the first "-" or "_"),
    /// when at least 3 channels and a fifth of them use it.
    static func commonPrefix(in names: [String]) -> (prefix: String, count: Int)? {
        var counts: [String: Int] = [:]
        for name in names {
            guard let cut = name.firstIndex(where: { $0 == "-" || $0 == "_" }) else { continue }
            let prefix = String(name[...cut])
            guard (2...13).contains(prefix.count) else { continue }
            counts[prefix, default: 0] += 1
        }
        guard let best = counts.max(by: { $0.value < $1.value }),
              best.value >= 3, Double(best.value) >= Double(names.count) * 0.2 else { return nil }
        return (best.key, best.value)
    }

    static func matches(_ a: String, _ b: String) -> Bool {
        slug(a) == slug(b)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var github: GitHubCredentials? { didSet { saveCredentials(); expired.remove(.github); GitHubStore.shared.reset() } }
    @Published var slack: SlackCredentials? {
        didSet { saveCredentials(); expired.remove(.slack); if slack?.teamID != oldValue?.teamID { SlackStore.shared.reset() } }
    }
    @Published var linear: LinearCredentials? { didSet { saveCredentials(); expired.remove(.linear) } }
    @Published var projects: [Project] = [] { didSet { saveProjects() } }
    /// How the team keeps its code; `perProject` is what Dever did before it was asked.
    @Published var repositoryMode: RepositoryMode {
        didSet { if simulatedMode == nil { UserDefaults.standard.set(repositoryMode.rawValue, forKey: RepositoryMode.key) } }
    }
    /// The one repository of `single` mode and the shared one of `mixed` mode (`owner/name`).
    @Published var workspaceRepository: String? {
        didSet { if simulatedMode == nil { UserDefaults.standard.set(workspaceRepository, forKey: RepositoryMode.workspaceKey) } }
    }
    /// How the Overview lists the projects (Settings › Overview, the page's View control).
    @Published var overview = OverviewSettings.load() { didSet { if overview != oldValue { overview.save() } } }
    @Published var lastError: String?
    /// Services whose token the service itself rejected since the last successful call.
    /// Connected but dead: Settings and the rail show "Reconnect" from here.
    @Published private(set) var expired: Set<ServiceKind> = []

    /// Snapshots: `DEVER_SNAPSHOT_DISCONNECTED=slack,linear` runs as if those services had no
    /// token (the Keychain is left alone); `DEVER_SNAPSHOT_UNAUTHORIZED=linear` as if the token
    /// were rejected; `DEVER_SNAPSHOT_FAILING=github,slack=offline` as if calls failed.
    private static func simulated(_ key: String) -> [String: String] {
        guard let raw = ProcessInfo.processInfo.environment[key] else { return [:] }
        var out: [String: String] = [:]
        for part in raw.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if let name = pair.first, !name.isEmpty { out[name] = pair.count > 1 ? pair[1] : "" }
        }
        return out
    }
    private let simulatedMissing = Set(simulated("DEVER_SNAPSHOT_DISCONNECTED").keys.compactMap(ServiceKind.init(rawValue:)))
    private let simulatedFailing = simulated("DEVER_SNAPSHOT_FAILING")
    private var simulatedMode: RepositoryMode?
    private var isSimulating: Bool {
        !simulatedMissing.isEmpty || !simulatedFailing.isEmpty || !Self.simulated("DEVER_SNAPSHOT_UNAUTHORIZED").isEmpty
            || PreviewStore.simulation != nil
    }

    private let projectsURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dever", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("projects.json")
    }()

    init() {
        repositoryMode = UserDefaults.standard.string(forKey: RepositoryMode.key).flatMap(RepositoryMode.init(rawValue:)) ?? .perProject
        workspaceRepository = UserDefaults.standard.string(forKey: RepositoryMode.workspaceKey)
        // Snapshots: DEVER_SNAPSHOT_REPO_MODE=single|perProject|mixed[:owner/name] runs under that mode.
        if let raw = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_REPO_MODE"] {
            let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
            simulatedMode = RepositoryMode(rawValue: parts[0])
            if let mode = simulatedMode {
                repositoryMode = mode
                if parts.count > 1 { workspaceRepository = parts[1] }
            }
        }
        // DEVER_SNAPSHOT_REPOS=owner/a,owner/b gives the first project those repositories (not saved).
        let simulatedRepos = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_REPOS"]?
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        if let stored = Keychain.load(StoredCredentials.self, for: Self.credentialsKey) {
            github = stored.github
            slack = stored.slack
            linear = stored.linear
        } else {
            // One-time migration from the former one-item-per-service layout.
            github = Keychain.load(GitHubCredentials.self, for: "github")
            slack = Keychain.load(SlackCredentials.self, for: "slack.oauth")
            linear = Keychain.load(LinearCredentials.self, for: "linear.oauth")
            saveCredentials()
            ["github", "slack.oauth", "linear.oauth", "slack", "linear"].forEach(Keychain.delete)
        }
        if let data = try? Data(contentsOf: projectsURL),
           let list = try? JSONDecoder().decode([Project].self, from: data) {
            projects = list
        }
        if !simulatedRepos.isEmpty, !projects.isEmpty {
            simulatedMode = simulatedMode ?? repositoryMode
            projects[0].githubRepos = simulatedRepos
            projects[0].usesWorkspaceRepository = false
        }
        // DEVER_SNAPSHOT_UNLINK=slack,linear,github,preview runs as if the captured project
        // (DEVER_SNAPSHOT_PROJECT) had not linked those tools. Nothing is written back.
        let unlink = Set(Self.simulated("DEVER_SNAPSHOT_UNLINK").keys)
        let captured = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_PROJECT"].flatMap(Int.init) ?? 0
        if !unlink.isEmpty, projects.indices.contains(captured) {
            // First, so the edits below are never saved: changing an element runs `projects.didSet`.
            simulatedMode = simulatedMode ?? repositoryMode
            if unlink.contains("slack") { projects[captured].slack = nil }
            if unlink.contains("linear") { projects[captured].linear = nil }
            if unlink.contains("github") { projects[captured].githubRepos = []; projects[captured].usesWorkspaceRepository = true }
            if unlink.contains("preview") { projects[captured].previewPullNumber = nil; projects[captured].previewDismissed = nil }
        }
        if simulatedMissing.contains(.slack) { slack = nil }
        if simulatedMissing.contains(.linear) { linear = nil }
        if simulatedMissing.contains(.github) { github = nil }
        // DEVER_SNAPSHOT_PREVIEW=live|deploying|failed|deleted|none: the first project follows the
        // sample pull request (none: no preview linked). Nothing is written back.
        if let mode = PreviewStore.simulation, !projects.isEmpty {
            projects[0].previewPullNumber = mode == "none" ? nil : PreviewStore.samplePullNumber
            if projects[0].githubRepos.isEmpty { projects[0].githubRepos = [PreviewStore.sampleRepo] }
            projects[0].previewRepository = projects[0].githubRepos.first
        }
        expired = Set(Self.simulated("DEVER_SNAPSHOT_UNAUTHORIZED").keys.compactMap(ServiceKind.init(rawValue:)))
    }

    /// Snapshot runs only: throws the failure the environment asks for.
    private func simulateFailure(_ s: ServiceKind) throws {
        if expired.contains(s), !Self.simulated("DEVER_SNAPSHOT_UNAUTHORIZED").isEmpty { throw AppError.unauthorized(s) }
        guard let mode = simulatedFailing[s.rawValue] else { return }
        switch mode {
        case "offline": throw URLError(.notConnectedToInternet)
        default: throw AppError.message("\(s.label) 503: service unavailable")
        }
    }

    /// Turns a failed call into a panel state and remembers a rejected token, so Settings
    /// and the rail can say "Reconnect" before the user opens the project again.
    /// Nil for a cancelled call (the page went away), which says nothing about the service.
    func failure(_ error: Error, _ s: ServiceKind) -> ServiceState? {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
        if case AppError.rateLimited(let service, let wait) = error {
            pausedUntil[service] = max(pausedUntil[service] ?? .distantPast, Date().addingTimeInterval(wait))
        }
        let state = ServiceState(error)
        if state == .unauthorized, !expired.contains(s) { expired.insert(s) }
        return state
    }

    /// A call that went through proves the token is alive again.
    func succeeded(_ s: ServiceKind) {
        if expired.contains(s) { expired.remove(s) }
    }

    /// The tools this project links that have no token: what the project page invites to connect.
    func missingServices(for p: Project) -> [ServiceKind] {
        var out: [ServiceKind] = []
        if p.slack != nil, slack == nil { out.append(.slack) }
        if p.linear != nil, linear == nil { out.append(.linear) }
        if !repositories(for: p).isEmpty, github == nil { out.append(.github) }
        return out
    }

    // MARK: Repositories

    /// The repositories a project follows: the workspace's in `single` mode, its own in
    /// `perProject`, either in `mixed`.
    func repositories(for p: Project) -> [String] {
        p.repositories(mode: repositoryMode, workspace: workspaceRepository)
    }

    /// Whether the project follows the workspace's shared repository: always in `single` mode,
    /// in `mixed` mode when it has no repositories of its own (or chose the shared one).
    func followsSharedRepository(_ p: Project) -> Bool {
        switch repositoryMode {
        case .single: true
        case .perProject: false
        case .mixed: p.usesWorkspaceRepository ?? p.githubRepos.isEmpty
        }
    }

    /// Whether the project counts every pull request of its repositories. Never on the shared
    /// repository, whose other pull requests belong to other projects: there only the pull
    /// requests linked to the project's Linear issues count.
    func showsWholeRepository(_ p: Project) -> Bool {
        !followsSharedRepository(p) && p.showsWholeRepository
    }

    /// On the shared repository without Linear issues to match, nothing tells this project's
    /// pull requests from the others': the GitHub part waits for a Linear project.
    func pullsNeedLinear(_ p: Project) -> Bool {
        followsSharedRepository(p) && p.linear == nil
    }

    /// The repository of the project's preview pull request, when the project still follows it.
    func previewRepository(for p: Project) -> String? {
        let repos = repositories(for: p)
        guard let repo = p.previewRepository ?? repos.first, repos.contains(repo) else { return nil }
        return repo
    }

    /// Whether the project page shows the Preview panel: a repository, and either a pull
    /// request to follow or no word yet on whether one is wanted.
    func showsPreview(_ p: Project) -> Bool {
        !repositories(for: p).isEmpty && (p.previewPullNumber != nil || p.previewDismissed != true)
    }

    /// Changes the mode without losing anything: a project's own repositories stay stored while
    /// `single` ignores them, and come back when the mode allows them again.
    func setRepositoryMode(_ mode: RepositoryMode, workspace: String?) {
        repositoryMode = mode
        workspaceRepository = workspace
    }

    func isConnected(_ s: ServiceKind) -> Bool {
        switch s {
        case .slack: slack != nil
        case .linear: linear != nil
        case .github: github != nil
        }
    }

    // MARK: Clients

    /// Until when each service asked not to be called (its `Retry-After`).
    private var pausedUntil: [ServiceKind: Date] = [:]

    /// While a service's pause lasts, calls to it fail here instead of being sent.
    private func respectPause(_ s: ServiceKind) throws {
        guard let until = pausedUntil[s] else { return }
        let left = until.timeIntervalSinceNow
        if left > 0 { throw AppError.rateLimited(s, retryAfter: left) }
        pausedUntil[s] = nil
    }

    func githubClient() throws -> GitHubClient {
        guard let github else { throw AppError.notConnected(.github) }
        try simulateFailure(.github)
        try respectPause(.github)
        return GitHubClient(token: github.token)
    }

    func withSlack<T>(_ body: (SlackClient) async throws -> T) async throws -> T {
        guard let slack else { throw AppError.notConnected(.slack) }
        try simulateFailure(.slack)
        try respectPause(.slack)
        let value = try await body(SlackClient(creds: slack))
        succeeded(.slack)
        return value
    }

    /// One refresh at a time: Linear rotates the refresh token, so two concurrent
    /// refreshes would invalidate the session.
    private var linearRefresh: Task<LinearCredentials, Error>?

    private func refreshedLinear(force: Bool) async throws -> LinearCredentials {
        guard let linear else { throw AppError.notConnected(.linear) }
        if !force && !linear.needsRefresh { return linear }
        if let linearRefresh { return try await linearRefresh.value }
        let task = Task { try await LinearAuth.refresh(linear) }
        linearRefresh = task
        defer { linearRefresh = nil }
        do {
            let fresh = try await task.value
            self.linear = fresh
            return fresh
        } catch AppError.unauthorized(.linear) {
            // The refresh token rotates: when another Dever process (a second window, a
            // snapshot run) refreshed first, ours is spent but its copy in the Keychain is
            // good. Take that before deciding the session is gone.
            if let stored = Keychain.load(StoredCredentials.self, for: Self.credentialsKey)?.linear,
               stored.accessToken != linear.accessToken, !stored.needsRefresh {
                self.linear = stored
                return stored
            }
            // The token stays: "connected, but rejected" is a different state from "not
            // connected", and the Settings row offers Reconnect for it.
            throw AppError.unauthorized(.linear)
        }
    }

    func withLinear<T>(_ body: (LinearClient) async throws -> T) async throws -> T {
        guard linear != nil else { throw AppError.notConnected(.linear) }
        try simulateFailure(.linear)
        try respectPause(.linear)
        let creds = try await refreshedLinear(force: false)
        let value: T
        do {
            value = try await body(LinearClient(token: creds.accessToken))
        } catch AppError.unauthorized(.linear) {
            let fresh = try await refreshedLinear(force: true)
            value = try await body(LinearClient(token: fresh.accessToken))
        }
        succeeded(.linear)
        return value
    }

    func disconnect(_ s: ServiceKind) {
        switch s {
        case .github: github = nil
        case .slack: slack = nil
        case .linear: linear = nil
        }
    }

    // MARK: Projects

    func upsert(_ project: Project) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.append(project)
        }
        projects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Pins or unpins a project on the Overview.
    func setFavorite(_ project: Project, _ on: Bool) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i].favorite = on ? true : nil
    }

    func delete(_ project: Project) {
        projects.removeAll { $0.id == project.id }
    }

    var linkedSlackIDs: Set<String> { Set(projects.compactMap { $0.slack?.id }) }
    var linkedLinearIDs: Set<String> { Set(projects.compactMap { $0.linear?.id }) }

    func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    // MARK: Persistence

    /// All tokens live in a single Keychain item, so macOS asks for access at most once.
    private struct StoredCredentials: Codable {
        var github: GitHubCredentials?
        var slack: SlackCredentials?
        var linear: LinearCredentials?
    }

    private static let credentialsKey = "credentials"

    private func saveCredentials() {
        // A snapshot run with simulated connections never writes its pretend state back.
        guard !isSimulating else { return }
        try? Keychain.save(StoredCredentials(github: github, slack: slack, linear: linear), for: Self.credentialsKey)
    }

    private func saveProjects() {
        // A snapshot run never writes the projects back, whatever it simulates.
        guard PreviewStore.simulation == nil, simulatedMode == nil, Snapshotter.directory == nil else { return }
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: projectsURL, options: .atomic)
        }
    }
}
