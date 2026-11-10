import Foundation
import SwiftUI

// A preview environment is the one deployed for a pull request by the team's GitHub
// workflows (`/preview` and `/delete-preview` comments; a push updates it; Saturday deletes
// it unless the PR carries `preview:keep`). Dever reads the workflows' own comments and runs
// and drives them the way a person would: by posting those comments.

/// The team's deploy targets. Hostnames are deterministic from the PR number
/// (`pr-<N>-<target>.<domain>`); only the targets the diff touched exist.
enum PreviewTarget: String, CaseIterable, Identifiable, Hashable {
    case app, api, bo, boapi, clienthub, clienthubAPI = "clienthub-api"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .app: "App"
        case .api: "API"
        case .bo: "Back office"
        case .boapi: "BO API"
        case .clienthub: "Client Hub"
        case .clienthubAPI: "Client Hub API"
        }
    }

    /// The domain the team's previews are served under (dever.json › `preview.domain`).
    static var domain: String { DeverConfig.shared.preview?.domain ?? "preview.example.com" }

    private static func host(_ target: PreviewTarget, pull: Int) -> String {
        "pr-\(pull)-\(target.rawValue).\(domain)"
    }

    static func url(_ target: PreviewTarget, pull: Int) -> URL {
        URL(string: "https://\(host(target, pull: pull))")!
    }

    /// The target of a preview URL found in a comment, if any.
    static func parse(_ url: String, pull: Int) -> PreviewTarget? {
        for target in allCases where url.contains(host(target, pull: pull)) {
            // "clienthub" is a prefix of "clienthub-api": the host must end right after it.
            if target == .clienthub, url.contains("pr-\(pull)-clienthub-api.") { continue }
            return target
        }
        return nil
    }
}

/// The flags of a `/preview` command.
struct PreviewOptions: Equatable {
    var apiPods: Int? = nil
    var appPods: Int? = nil
    var prod = false
    var autoscale = false
    var keep = false

    /// The exact comment the workflow parses.
    var command: String {
        var parts = ["/preview"]
        if let apiPods { parts.append("--nb-api-pods=\(apiPods)") }
        if let appPods { parts.append("--nb-app-pods=\(appPods)") }
        if prod { parts.append("--prod") }
        if autoscale { parts.append("--autoscale") }
        if keep { parts.append("--keep") }
        return parts.joined(separator: " ")
    }

    /// Reads the flags back from a comment that carried the command.
    static func parse(_ body: String) -> PreviewOptions {
        var o = PreviewOptions()
        func value(_ flag: String) -> Int? {
            guard let r = body.range(of: "--\(flag)\\s*=\\s*(\\d+)", options: .regularExpression) else { return nil }
            return Int(body[r].split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        o.apiPods = value("nb-api-pods")
        o.appPods = value("nb-app-pods")
        o.prod = body.contains("--prod")
        o.autoscale = body.contains("--autoscale")
        o.keep = body.contains("--keep")
        return o
    }
}

/// What the preview of one pull request is doing, read from the workflows' comments.
struct PreviewStatus: Equatable {
    enum Phase: Equatable {
        /// No result comment yet, or nothing to deploy.
        case notDeployed
        case deploying, updating, deleting
        case live
        case failed
        case deleted

        var word: String {
            switch self {
            case .notDeployed: "Not deployed"
            case .deploying: "Deploying"
            case .updating: "Updating"
            case .deleting: "Deleting"
            case .live: "Live"
            case .failed: "Failed"
            case .deleted: "Deleted"
            }
        }

        var busy: Bool { self == .deploying || self == .updating || self == .deleting }
    }

    struct Pull: Equatable {
        enum State: String { case open, draft, merged, closed
            var word: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
        }
        var number: Int
        var title: String
        var url: URL
        var author: String
        var state: State
        var headRef: String
    }

    struct Run: Equatable {
        var url: URL
        var inProgress: Bool
        var failed: Bool
        var step: String?
        var createdAt: Date
    }

    var phase: Phase
    var pull: Pull
    /// The targets the latest results listed, with what the probe found (nil: not probed).
    var targets: [PreviewTarget: Bool?] = [:]
    /// The `preview:keep` label on the PR: protected from the Saturday cleanup.
    var keep = false
    /// The flags of the last `/preview` posted, the next deploy's defaults.
    var options = PreviewOptions()
    /// When the latest status comment was posted.
    var updatedAt: Date?
    var run: Run?
    /// One line from the workflow when it failed or declined.
    var note: String?
    /// When the latest `/preview` or `/delete-preview` was posted (to find its run).
    var commandAt: Date?

    var sortedTargets: [PreviewTarget] { PreviewTarget.allCases.filter { targets[$0] != nil } }
    var appURL: URL? { targets[.app] != nil ? PreviewTarget.url(.app, pull: pull.number) : nil }
}

/// A project's preview as the panel sees it: loading, loaded, or why not.
enum PreviewState: Equatable {
    case loading
    case loaded(PreviewStatus)
    case failed(ServiceState)

    var status: PreviewStatus? { if case .loaded(let s) = self { s } else { nil } }
}

/// Loads and caches each project's preview status, and posts the commands. One copy for the
/// app: the overview row and the project page read the same status.
@MainActor
final class PreviewStore: ObservableObject {
    static let shared = PreviewStore()

    @Published private(set) var states: [UUID: PreviewState] = [:]
    @Published private(set) var loadedAt: [UUID: Date] = [:]
    /// Projects whose command was just posted: polled every 30 s until the phase moves.
    @Published private(set) var awaiting: [UUID: PreviewStatus.Phase] = [:]
    private var loads: [UUID: Task<Void, Never>] = [:]
    private var polls: [UUID: Task<Void, Never>] = [:]

    static let deployWorkflow = "pr-preview-deploy-new-environment.yml"
    static let updateWorkflow = "pr-preview-on-new-commit.yml"
    static let cleanupWorkflow = "pr-preview-cleanup.yml"
    static let keepLabel = "preview:keep"
    /// An in-progress comment older than this with no result after it: the run died.
    static let stuckAfter: TimeInterval = 45 * 60

    // MARK: Snapshots

    /// `DEVER_SNAPSHOT_PREVIEW=live|deploying|failed|deleted|notdeployed|none` renders that
    /// state from sample data, without network.
    static let simulation: String? = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_PREVIEW"]
    static let samplePullNumber = 4714
    static let sampleRepo = "acme/platform"

    /// Open pull requests for the editor's picker in a snapshot run.
    static var samplePulls: [GitHubPull] {
        func pull(_ n: Int, _ title: String, _ login: String, _ ref: String, draft: Bool = false) -> GitHubPull {
            GitHubPull(id: n, number: n, title: title, html_url: "https://github.com/\(sampleRepo)/pull/\(n)", draft: draft,
                       user: .init(login: login), updated_at: "2026-11-05T09:00:00Z", head: .init(ref: ref), merged_at: nil)
        }
        return [pull(4714, "feat(app): guided lab intro with the new side panel [ENG-1050]", "ada", "feat/eng-1050-lab-intro"),
                pull(4720, "fix(api): rate-limit tip translations [ENG-1055]", "grace", "fix/eng-1055-translations"),
                pull(4718, "chore: bump node to 22", "linus", "chore/node-22", draft: true),
                pull(4711, "feat(bo): client hub billing export", "margaret", "feat/billing-export")]
    }

    static func sample(_ mode: String) -> PreviewStatus? {
        let pull = PreviewStatus.Pull(number: samplePullNumber, title: "feat(app): guided lab intro with the new side panel [ENG-1050]",
                                      url: URL(string: "https://github.com/\(sampleRepo)/pull/\(samplePullNumber)")!,
                                      author: "ada", state: .open, headRef: "feat/eng-1050-lab-intro")
        let run = PreviewStatus.Run(url: URL(string: "https://github.com/\(sampleRepo)/actions/runs/19284738291")!,
                                    inProgress: false, failed: false, step: nil, createdAt: Date().addingTimeInterval(-12 * 60))
        var s = PreviewStatus(phase: .live, pull: pull)
        switch mode {
        case "live":
            s.targets = [.app: true, .api: true, .bo: false]
            s.keep = true
            s.options = PreviewOptions(prod: false, autoscale: false, keep: true)
            s.updatedAt = Date().addingTimeInterval(-12 * 60)
            s.run = run
        case "deploying":
            s.phase = .deploying
            s.updatedAt = Date().addingTimeInterval(-3 * 60)
            s.run = PreviewStatus.Run(url: run.url, inProgress: true, failed: false, step: "Build and push API image",
                                      createdAt: Date().addingTimeInterval(-3 * 60))
        case "failed":
            s.phase = .failed
            s.updatedAt = Date().addingTimeInterval(-25 * 60)
            s.run = PreviewStatus.Run(url: run.url, inProgress: false, failed: true, step: nil, createdAt: Date().addingTimeInterval(-35 * 60))
            s.note = "The deploy failed. The run's logs say why."
        case "deleted":
            s.phase = .deleted
            s.updatedAt = Date().addingTimeInterval(-2 * 86_400)
        case "notdeployed":
            s.phase = .notDeployed
        default:
            return nil
        }
        return s
    }

    // MARK: Reading

    func state(for project: Project) -> PreviewState? {
        project.previewPullNumber == nil ? nil : states[project.id]
    }

    /// Loads the project's preview unless it was loaded within the last minute (`force`
    /// ignores that). Concurrent calls share one load.
    func load(_ project: Project, app: AppState, force: Bool = false) async {
        guard let number = project.previewPullNumber, let repo = app.previewRepository(for: project) else {
            states[project.id] = nil
            return
        }
        if let task = loads[project.id] { await task.value; return }
        if !force, let at = loadedAt[project.id], Date().timeIntervalSince(at) < 60, states[project.id]?.status != nil { return }
        if states[project.id] == nil { states[project.id] = .loading }
        let task = Task { [weak self] in
            guard let self else { return }
            if let mode = Self.simulation {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if let sample = Self.sample(mode) { self.states[project.id] = .loaded(sample) }
                self.loadedAt[project.id] = Date()
                return
            }
            do {
                let client = try app.githubClient()
                let status = try await Self.fetch(repo: repo, number: number, client: client, previous: self.states[project.id]?.status)
                self.states[project.id] = .loaded(status)
                app.succeeded(.github)
            } catch {
                if let state = app.failure(error, .github) {
                    // A loaded status outlives a failed refresh: the row says what it last knew.
                    if self.states[project.id]?.status == nil { self.states[project.id] = .failed(state) }
                }
            }
            self.loadedAt[project.id] = Date()
        }
        loads[project.id] = task
        await task.value
        loads[project.id] = nil
    }

    /// The overview's cycle: every project with a preview, a few at a time.
    func refreshAll(_ projects: [Project], app: AppState) async {
        let withPreview = projects.filter { $0.previewPullNumber != nil && app.previewRepository(for: $0) != nil }
        guard !withPreview.isEmpty else { states = [:]; return }
        let ids = Set(withPreview.map(\.id))
        states = states.filter { ids.contains($0.key) }
        await withTaskGroup(of: Void.self) { group in
            for p in withPreview { group.addTask { await self.load(p, app: app) } }
        }
    }

    private static func fetch(repo: String, number: Int, client: GitHubClient, previous: PreviewStatus?) async throws -> PreviewStatus {
        let detail = try await client.pull(repo, number: number)
        async let comments = client.latestComments(repo, number: number, total: detail.comments)
        async let deployRuns = client.workflowRuns(repo, file: deployWorkflow, limit: 10)
        async let cleanupRuns = client.workflowRuns(repo, file: cleanupWorkflow, limit: 5)
        async let updateRuns = client.workflowRuns(repo, file: updateWorkflow, branch: detail.head.ref, limit: 5)

        let pullState: PreviewStatus.Pull.State = detail.merged_at != nil ? .merged
            : detail.state == "closed" ? .closed : detail.draft == true ? .draft : .open
        let pull = PreviewStatus.Pull(number: number, title: detail.title, url: URL(string: detail.html_url)!,
                                      author: detail.user.login, state: pullState, headRef: detail.head.ref)
        var status = derive(from: try await comments, pull: pull)
        status.keep = detail.labels.contains { $0.name == keepLabel }

        // The run behind the latest command or push, for its link and its progress.
        let runs = (try await deployRuns) + (try await cleanupRuns) + (try await updateRuns)
        if let run = latestRun(runs, after: status.commandAt, pull: pull) {
            var info = PreviewStatus.Run(url: URL(string: run.html_url)!,
                                         inProgress: run.status != "completed",
                                         failed: ["failure", "timed_out", "cancelled"].contains(run.conclusion ?? ""),
                                         step: nil, createdAt: Self.date(run.created_at) ?? Date())
            if info.inProgress {
                info.step = try? await client.runSteps(repo, runID: run.id)?.step
                // The run knows better than the comments while it is going.
                if !status.phase.busy, info.createdAt >= (status.updatedAt ?? .distantPast) {
                    status.phase = run.event == "pull_request" ? .updating
                        : run.name?.lowercased().contains("cleanup") == true ? .deleting : .deploying
                }
            } else if info.failed, info.createdAt > (status.updatedAt ?? .distantPast), status.phase.busy {
                status.phase = .failed
                status.note = status.note ?? "The workflow run did not finish."
            }
            status.run = info
        }

        // A started comment with nothing after it for long: the run died without saying so.
        if status.phase.busy, let at = status.updatedAt, Date().timeIntervalSince(at) > stuckAfter,
           status.run?.inProgress != true {
            status.phase = .failed
            status.note = "The workflow started but never reported back."
        }

        // The PR is gone: so is its preview (the close workflow deletes it).
        if pullState == .closed || pullState == .merged, status.phase != .deleted, !status.phase.busy {
            status.phase = .deleted
        }

        if status.phase == .live {
            // Which hosts answer, a few seconds at most, all at once.
            let targets = status.sortedTargets
            let reachable = await withTaskGroup(of: (PreviewTarget, Bool).self) { group in
                for t in targets { group.addTask { (t, await GitHubClient.isReachable(PreviewTarget.url(t, pull: number))) } }
                var out: [PreviewTarget: Bool] = [:]
                for await (t, ok) in group { out[t] = ok }
                return out
            }
            for t in targets { status.targets[t] = reachable[t] }
        }
        return status
    }

    /// Replays the comments oldest to newest, keeping the state the latest one leaves.
    static func derive(from comments: [GitHubComment], pull: PreviewStatus.Pull) -> PreviewStatus {
        var s = PreviewStatus(phase: .notDeployed, pull: pull)
        var live: Set<PreviewTarget> = []
        for c in comments.sorted(by: { $0.created_at < $1.created_at }) {
            guard let body = c.body else { continue }
            let at = date(c.created_at)
            let urls = body.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == ")" || $0 == "<" || $0 == ">" })
                .compactMap { PreviewTarget.parse(String($0), pull: pull.number) }
            if body.range(of: #"(^|\s)/preview\b"#, options: .regularExpression) != nil {
                s.options = PreviewOptions.parse(body)
                s.commandAt = at
                continue
            }
            if body.contains("/delete-preview") { s.commandAt = at; continue }
            if body.contains("Environnement de preview déployé") {
                s.phase = .live; live = Set(urls); s.note = nil
            } else if body.contains("Environnement de preview mis à jour") {
                s.phase = .live; live.formUnion(urls); s.note = nil
            } else if body.contains("Aucune mise à jour effectuée") {
                s.phase = live.isEmpty ? .notDeployed : .live
            } else if body.contains("Déploiement de l'environnement de preview en cours") {
                s.phase = .deploying
            } else if body.contains("Nouveau commit détecté") {
                s.phase = .updating
            } else if body.contains("Starting preview environment cleanup") {
                s.phase = .deleting
            } else if body.contains("Preview environment successfully deleted") || body.contains("a été automatiquement supprimé") {
                s.phase = .deleted; live = []
            } else if body.contains("Aucun environnement de preview créé") {
                s.phase = live.isEmpty ? .notDeployed : .live
                s.note = "Nothing to deploy: the diff touches none of the deployable folders."
            } else if let note = failureNote(body) {
                s.phase = .failed
                s.note = note
            } else {
                continue
            }
            s.updatedAt = at
        }
        s.targets = Dictionary(uniqueKeysWithValues: live.map { ($0, Bool?.none) })
        return s
    }

    /// The run that answered the latest command (issue_comment runs start within a minute of
    /// it) or the latest push of the PR's branch, newest first.
    private static func latestRun(_ runs: [GitHubRun], after command: Date?, pull: PreviewStatus.Pull) -> GitHubRun? {
        let sorted = runs.sorted { $0.created_at > $1.created_at }
        return sorted.first { run in
            guard let created = date(run.created_at) else { return false }
            switch run.event {
            case "pull_request", "push": return run.head_branch == pull.headRef
            case "issue_comment", "workflow_dispatch":
                guard let command else { return false }
                return created >= command.addingTimeInterval(-90) && created <= command.addingTimeInterval(15 * 60)
            default: return false
            }
        }
    }

    /// The workflow's failure comments, said in Dever's words; nil for any other comment.
    static func failureNote(_ body: String) -> String? {
        if body.contains("Environnement de preview non créé") { return "Nothing deployed: a build failed. The run's logs say which." }
        if body.contains("Le déploiement de l'environnement de preview a échoué") { return "The deploy failed. The run's logs say why." }
        if body.contains("Mise à jour de la preview échouée") || body.contains("La mise à jour automatique") {
            return "The update failed. The run's logs say why."
        }
        if body.contains("Failed to delete preview environment") { return "The delete failed. The run's logs say why." }
        if body.contains("pas la permission") || body.contains("permission to delete") {
            return "GitHub refused the command: your account cannot manage previews on this repository."
        }
        return nil
    }

    private static func firstLine(_ body: String) -> String {
        let line = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? body
        return line.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[^\w(]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
    }

    static func date(_ iso: String) -> Date? { ISO8601DateFormatter().date(from: iso) }

    // MARK: Acting

    /// Posts `/preview …` on the PR: a deploy, or an update of a live preview.
    func deploy(_ project: Project, app: AppState, options: PreviewOptions) async throws {
        let live = state(for: project)?.status?.phase == .live
        try await post(project, app: app, body: options.command, then: live ? .updating : .deploying)
    }

    func delete(_ project: Project, app: AppState) async throws {
        try await post(project, app: app, body: "/delete-preview", then: .deleting)
    }

    private func post(_ project: Project, app: AppState, body: String, then phase: PreviewStatus.Phase) async throws {
        guard let number = project.previewPullNumber, let repo = app.previewRepository(for: project) else { return }
        if Self.simulation == nil {
            _ = try await app.githubClient().comment(repo, number: number, body: body)
        }
        // Say so at once, then watch the runs until the workflow answers.
        if var status = states[project.id]?.status {
            status.phase = phase
            status.updatedAt = Date()
            status.note = nil
            status.run = nil
            if body.hasPrefix("/preview") { status.options = PreviewOptions.parse(body) }
            states[project.id] = .loaded(status)
        }
        awaiting[project.id] = phase
        polls[project.id]?.cancel()
        polls[project.id] = Task { [weak self] in
            // Up to 40 minutes, every 30 s: a deploy takes about ten.
            for _ in 0..<80 {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.load(project, app: app, force: true)
                if let now = self.states[project.id]?.status?.phase, !now.busy { break }
            }
            self?.awaiting[project.id] = nil
        }
    }

    /// Lets go of a project (removed, or its preview unlinked).
    func forget(_ id: UUID) {
        polls[id]?.cancel(); polls[id] = nil
        states[id] = nil; loadedAt[id] = nil; awaiting[id] = nil
    }
}
