import Foundation
import SwiftUI

/// Linear issues kept in memory across screens, so the project page and the issue page share
/// one copy and going back and forth costs no request. Lists refresh by delta (issues changed
/// since the last load, merged by `id`); details are fetched once per `id + updatedAt`; team
/// states and members live a quarter of an hour. Linear allows 1,500 requests an hour per
/// user, which this keeps far away.
@MainActor
final class IssueStore: ObservableObject {
    static let shared = IssueStore()

    struct ProjectIssues {
        var issues: [LinearIssue]
        var lastFullLoad: Date
        /// The last load of any kind, full or delta.
        var lastLoad = Date()
        /// Linear's `updatedAt` of the newest issue seen, the cursor of the next delta.
        var newest: String?
    }

    /// A pull request the project page knows, so an issue's GitHub attachment can show it.
    struct PullRef: Hashable {
        enum State { case open, draft, merged
            var label: String { switch self { case .open: "Open"; case .draft: "Draft"; case .merged: "Merged" } }
        }
        var number: Int
        var title: String
        var state: State
        /// The Linear identifier Dever matched it to (branch, title or Linear's attachment).
        var issue: String? = nil
        /// Merged: when it merged. Open: its last update.
        var date: Date? = nil
        var author: String? = nil
    }

    @Published private(set) var projects: [String: ProjectIssues] = [:]
    /// Pull requests by their GitHub URL, filled by the project page.
    @Published var pullsByURL: [String: PullRef] = [:]
    @Published private(set) var details: [String: LinearIssueDetail] = [:]
    /// The viewer's Linear user id, asked once.
    @Published private(set) var viewerID: String?
    /// For each project, its blocked issues and the unfinished issues blocking them.
    @Published private(set) var blockers: [String: [String: [String]]] = [:]
    /// Rendered descriptions and comment bodies, keyed by text hash: rendering is the slow part.
    @Published private(set) var rendered: [Int: [MarkdownBlock]] = [:]
    private var teams: [String: (context: LinearTeamContext, at: Date)] = [:]
    private var facts: [String: (facts: LinearProjectFacts, at: Date)] = [:]
    private var listLoads: [String: Task<[LinearIssue], Error>] = [:]
    private var detailLoads: [String: Task<LinearIssueDetail, Error>] = [:]
    private var teamLoads: [String: Task<LinearTeamContext, Error>] = [:]
    private var renders: [Int: Task<[MarkdownBlock], Never>] = [:]
    private let fullReloadAfter: TimeInterval = 30 * 60
    private let teamTTL: TimeInterval = 15 * 60

    func issues(project id: String) -> [LinearIssue] { projects[id]?.issues ?? [] }

    func row(_ issueID: String) -> LinearIssue? {
        for p in projects.values { if let i = p.issues.first(where: { $0.id == issueID }) { return i } }
        return details[issueID]?.asRow
    }

    // MARK: Lists

    /// Loads a project's issues: all of them the first time or after half an hour, otherwise
    /// only those changed since the last load. `force` reloads everything (the Refresh button).
    /// The list is served as it is when it was loaded within `maxAge`, and readers asking at
    /// the same moment (the Overview's cycle and a project page) share one request.
    func load(project id: String, force: Bool = false, maxAge: TimeInterval = 0, app: AppState) async throws -> [LinearIssue] {
        if !force, let known = projects[id], Date().timeIntervalSince(known.lastLoad) < maxAge { return known.issues }
        if let running = listLoads[id] { return try await running.value }
        let task = Task { try await self.fetch(project: id, force: force, app: app) }
        listLoads[id] = task
        defer { listLoads[id] = nil }
        return try await task.value
    }

    private func fetch(project id: String, force: Bool, app: AppState) async throws -> [LinearIssue] {
        let known = projects[id]
        let delta = !force && known != nil && Date().timeIntervalSince(known!.lastFullLoad) < fullReloadAfter
        let fetched = try await app.withLinear { try await $0.issues(projectID: id, updatedSince: delta ? known?.newest : nil) }
        var merged: [String: LinearIssue] = delta ? Dictionary(uniqueKeysWithValues: (known?.issues ?? []).map { ($0.id, $0) }) : [:]
        for issue in fetched {
            if issue.archivedAt != nil { merged[issue.id] = nil } else { merged[issue.id] = issue }
        }
        let list = merged.values.sorted { $0.updatedAt > $1.updatedAt }
        projects[id] = ProjectIssues(issues: list, lastFullLoad: delta ? known!.lastFullLoad : Date(),
                                     newest: list.first?.updatedAt ?? known?.newest)
        // A changed issue invalidates its cached detail; the next visit fetches it again.
        for issue in fetched where details[issue.id]?.updatedAt != issue.updatedAt { details[issue.id] = nil }
        return list
    }

    /// The project's lead, team and target date, asked a quarter of an hour apart at most.
    func facts(project id: String, app: AppState) async throws -> LinearProjectFacts {
        if let hit = facts[id], Date().timeIntervalSince(hit.at) < teamTTL { return hit.facts }
        let found = try await app.withLinear { try await $0.projectFacts(id: id) }
        facts[id] = (found, Date())
        return found
    }

    /// What the delivery plan needs beyond the rows: who is looking, and what blocks what.
    /// Neither is worth failing the list for, so errors leave the previous values.
    func loadPlanContext(project id: String, app: AppState) async {
        if viewerID == nil { viewerID = try? await app.withLinear { try await $0.viewerID() } }
        if let found = try? await app.withLinear({ try await $0.blockers(projectID: id) }) { blockers[id] = found }
    }

    // MARK: Details

    /// The issue's full record. `updatedAt` is the list's; a cached detail with the same value
    /// is returned at once, a stale one is replaced.
    func detail(_ id: String, updatedAt: String?, app: AppState) async throws -> LinearIssueDetail {
        if let cached = details[id], updatedAt == nil || cached.updatedAt == updatedAt { return cached }
        if let running = detailLoads[id] { return try await running.value }
        let task = Task { try await app.withLinear { try await $0.issueDetail(id: id) } }
        detailLoads[id] = task
        defer { detailLoads[id] = nil }
        let detail = try await task.value
        details[id] = detail
        apply(detail.asRow)
        return detail
    }

    func cachedDetail(_ id: String) -> LinearIssueDetail? { details[id] }

    func team(_ id: String, app: AppState) async throws -> LinearTeamContext {
        if let hit = teams[id], Date().timeIntervalSince(hit.at) < teamTTL { return hit.context }
        if let running = teamLoads[id] { return try await running.value }
        let task = Task { try await app.withLinear { try await $0.teamContext(id: id) } }
        teamLoads[id] = task
        defer { teamLoads[id] = nil }
        let context = try await task.value
        teams[id] = (context, Date())
        return context
    }

    // MARK: Changes

    /// Writes a row into every list and detail that holds the issue (optimistic or confirmed).
    func apply(_ row: LinearIssue) {
        for (pid, var p) in projects {
            guard let i = p.issues.firstIndex(where: { $0.id == row.id }) else { continue }
            var kept = p.issues[i]
            kept.state = row.state; kept.assignee = row.assignee; kept.priority = row.priority
            kept.dueDate = row.dueDate; kept.labels = row.labels; kept.title = row.title; kept.updatedAt = row.updatedAt
            p.issues[i] = kept
            projects[pid] = p
        }
        if var d = details[row.id] {
            d.state = row.state; d.assignee = row.assignee; d.priority = row.priority ?? d.priority
            d.priorityLabel = LinearPriority.label(row.priority); d.updatedAt = row.updatedAt
            details[row.id] = d
        }
    }

    /// Applies a change on the server. The caller has already shown the new value; on failure
    /// the previous row is restored and the error rethrown.
    func update(_ id: String, change: LinearClient.IssueChange, optimistic: LinearIssue, previous: LinearIssue, app: AppState) async throws {
        apply(optimistic)
        do {
            let confirmed = try await app.withLinear { try await $0.updateIssue(id: id, change: change) }
            apply(confirmed)
        } catch {
            apply(previous)
            throw error
        }
    }

    // MARK: Markdown

    /// Rendered blocks for `text`, parsed off the main thread the first time and kept.
    func blocks(for text: String) async -> [MarkdownBlock] {
        let key = text.hashValue
        if let hit = rendered[key] { return hit }
        if let running = renders[key] { return await running.value }
        let task = Task.detached(priority: .userInitiated) { MarkdownBlocks.parse(text) }
        renders[key] = task
        let blocks = await task.value
        renders[key] = nil
        rendered[key] = blocks
        return blocks
    }
}
