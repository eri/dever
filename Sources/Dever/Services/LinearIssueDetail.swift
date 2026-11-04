import Foundation

/// Everything the issue page shows, from one GraphQL query: the issue, its relations,
/// sub-issues, attachments and comments.
struct LinearIssueDetail: Codable, Hashable, Identifiable {
    struct Brief: Codable, Hashable, Identifiable {
        var id: String
        var identifier: String
        var title: String
        var url: String
        var state: LinearIssue.State
        var assignee: LinearIssue.Person?
        var priority: Int?
    }
    struct Briefs: Codable, Hashable { var nodes: [Brief] }
    struct Relation: Codable, Hashable {
        /// "blocks", "duplicate", "related".
        var type: String
        var relatedIssue: Brief?
    }
    struct InverseRelation: Codable, Hashable {
        var type: String
        var issue: Brief?
    }
    struct Relations: Codable, Hashable { var nodes: [Relation] }
    struct InverseRelations: Codable, Hashable { var nodes: [InverseRelation] }
    struct Attachment: Codable, Hashable, Identifiable {
        var id: String
        var url: String
        var title: String?
        var subtitle: String?
        var sourceType: String?
    }
    struct AttachmentList: Codable, Hashable { var nodes: [Attachment] }
    struct Comment: Codable, Hashable, Identifiable {
        struct Parent: Codable, Hashable { var id: String }
        struct Bot: Codable, Hashable { var name: String? }
        var id: String
        var body: String
        var createdAt: String
        var updatedAt: String
        var user: LinearIssue.Person?
        var botActor: Bot?
        var parent: Parent?
        var authorName: String { user?.name ?? botActor?.name ?? "Linear" }
    }
    struct Comments: Codable, Hashable { var nodes: [Comment] }
    struct Cycle: Codable, Hashable { var number: Int; var name: String? }
    struct Milestone: Codable, Hashable { var name: String }
    struct Team: Codable, Hashable { var id: String; var key: String }

    var id: String
    var identifier: String
    var title: String
    var description: String?
    var url: String
    var createdAt: String
    var updatedAt: String
    var priority: Int
    var priorityLabel: String
    var estimate: Double?
    var dueDate: String?
    var state: LinearIssue.State
    var assignee: LinearIssue.Person?
    var labels: LinearIssue.Labels?
    var cycle: Cycle?
    var projectMilestone: Milestone?
    var parent: Brief?
    var children: Briefs?
    var relations: Relations?
    var inverseRelations: InverseRelations?
    var attachments: AttachmentList?
    var comments: Comments?
    var team: Team?

    var labelList: [LinearIssue.Label] { labels?.nodes ?? [] }
    var subIssues: [Brief] { children?.nodes ?? [] }
    /// Issues this one blocks.
    var blocks: [Brief] { (relations?.nodes ?? []).filter { $0.type == "blocks" }.compactMap(\.relatedIssue) }
    /// Issues that block this one.
    var blockedBy: [Brief] { (inverseRelations?.nodes ?? []).filter { $0.type == "blocks" }.compactMap(\.issue) }
    var related: [Brief] {
        (relations?.nodes ?? []).filter { $0.type == "related" }.compactMap(\.relatedIssue)
            + (inverseRelations?.nodes ?? []).filter { $0.type == "related" }.compactMap(\.issue)
    }
    /// Oldest first, as a thread reads.
    var thread: [Comment] { (comments?.nodes ?? []).sorted { $0.createdAt < $1.createdAt } }

    /// The row-level view of this issue, so a list can be updated from a detail.
    var asRow: LinearIssue {
        LinearIssue(id: id, identifier: identifier, title: title, url: url, updatedAt: updatedAt, state: state,
                    assignee: assignee, branchName: nil,
                    attachments: Attachments(nodes: (attachments?.nodes ?? []).map { .init(url: $0.url) }),
                    priority: priority, dueDate: dueDate, labels: labels, archivedAt: nil)
    }
}

/// A team's workflow states and members: the choices behind the triage menus.
struct LinearTeamContext: Codable, Hashable {
    struct WorkflowState: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var type: String
        var color: String
        var position: Double
    }
    struct Member: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var avatarUrl: String?
        var active: Bool?
    }
    var states: [WorkflowState]
    var members: [Member]

    /// Linear's column order: triage, backlog, to do, started, done, canceled; then by position.
    var orderedStates: [WorkflowState] {
        let order = ["triage": 0, "backlog": 1, "unstarted": 2, "started": 3, "completed": 4, "canceled": 5]
        return states.sorted {
            let a = order[$0.type] ?? 9, b = order[$1.type] ?? 9
            return a == b ? $0.position < $1.position : a < b
        }
    }
}

/// Linear's priority scale, with the words Linear uses.
enum LinearPriority {
    static let all: [(value: Int, label: String)] = [(0, "No priority"), (1, "Urgent"), (2, "High"), (3, "Medium"), (4, "Low")]
    static func label(_ value: Int?) -> String { all.first { $0.value == value }?.label ?? "No priority" }
}

extension LinearClient {
    func issueDetail(id: String) async throws -> LinearIssueDetail {
        struct R: Decodable { var issue: LinearIssueDetail }
        let brief = "id identifier title url state { id name type color } assignee { id name avatarUrl } priority"
        return try await query("""
        query($id: String!) { issue(id: $id) {
          id identifier title description url createdAt updatedAt priority priorityLabel estimate dueDate
          state { id name type color } assignee { id name avatarUrl }
          labels { nodes { id name color } }
          cycle { number name } projectMilestone { name } team { id key }
          parent { \(brief) }
          children(first: 50) { nodes { \(brief) } }
          relations(first: 50) { nodes { type relatedIssue { \(brief) } } }
          inverseRelations(first: 50) { nodes { type issue { \(brief) } } }
          attachments(first: 50) { nodes { id url title subtitle sourceType } }
          comments(first: 100) { nodes { id body createdAt updatedAt user { id name avatarUrl } botActor { name } parent { id } } }
        } }
        """, variables: ["id": id], as: R.self).issue
    }

    func teamContext(id: String) async throws -> LinearTeamContext {
        struct R: Decodable {
            struct T: Decodable {
                struct S: Decodable { var nodes: [LinearTeamContext.WorkflowState] }
                struct M: Decodable { var nodes: [LinearTeamContext.Member] }
                var states: S; var members: M
            }
            var team: T
        }
        let t = try await query("""
        query($id: String!) { team(id: $id) {
          states(first: 50) { nodes { id name type color position } }
          members(first: 250) { nodes { id name avatarUrl active } } } }
        """, variables: ["id": id], as: R.self).team
        return LinearTeamContext(states: t.states.nodes, members: t.members.nodes.filter { $0.active != false })
    }

    struct IssueChange {
        var stateID: String?
        /// `.some(nil)` unassigns.
        var assigneeID: String??
        var priority: Int?
    }

    /// Applies one triage change; the returned row carries Linear's own `updatedAt`.
    func updateIssue(id: String, change: IssueChange) async throws -> LinearIssue {
        struct R: Decodable {
            struct P: Decodable { var success: Bool; var issue: LinearIssue? }
            var issueUpdate: P
        }
        var input: [String: Any] = [:]
        if let s = change.stateID { input["stateId"] = s }
        if let a = change.assigneeID { input["assigneeId"] = a ?? NSNull() }
        if let p = change.priority { input["priority"] = p }
        let r = try await query("""
        mutation($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) {
          success issue { \(Self.issueRowFields) } } }
        """, variables: ["id": id, "input": input], as: R.self).issueUpdate
        guard r.success, let issue = r.issue else { throw AppError.message("Linear did not accept the change.") }
        return issue
    }

    /// Adds the bearer token for pictures on `uploads.linear.app`, which refuse anonymous requests.
    func authorize(_ req: inout URLRequest) {
        guard let host = req.url?.host, host.hasSuffix("linear.app") else { return }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}
