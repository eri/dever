import Foundation

// What an agent proposes when it has finished (docs/agents-integration.md, phase 4): an account of
// what it did and did not verify, and the follow-up it suggests (move the issue, answer the
// thread). A proposal writes nothing: the developer applies it, edits it or dismisses it.

/// One agent's proposal for one issue.
struct AgentProposal: Equatable {
    var tool: AgentTool
    /// The issue's identifier as Linear writes it.
    var identifier: String
    var summary: String
    var notVerified: String?
    /// The name of the workflow state the agent suggests.
    var status: String?
    /// The reply the agent suggests for the issue's Slack thread.
    var reply: String?
    var at: Date
    /// What the developer did with it: the state the issue was moved to, the reply sent.
    var movedTo: String?
    var replied = false
    var statusDismissed = false
    var replyDismissed = false

    /// Something is still waiting for the developer's word.
    var pending: Bool {
        (status != nil && movedTo == nil && !statusDismissed) || (reply != nil && !replied && !replyDismissed)
    }

    /// From the arguments of `propose_update`; nil without a summary.
    init?(tool: AgentTool, arguments: [String: String], at: Date) {
        func clean(_ key: String) -> String? {
            let text = arguments[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
        guard let identifier = clean("issue"), let summary = clean("summary") else { return nil }
        self.tool = tool
        self.identifier = identifier
        self.summary = summary
        notVerified = clean("not_verified")
        status = clean("status")
        reply = clean("reply")
        self.at = at
    }

    /// The team's state the suggested name means: the same name, else the one that contains it.
    func state(in states: [LinearTeamContext.WorkflowState]) -> LinearTeamContext.WorkflowState? {
        guard let wanted = status?.lowercased() else { return nil }
        return states.first { $0.name.lowercased() == wanted }
            ?? states.first { $0.name.lowercased().contains(wanted) || wanted.contains($0.name.lowercased()) }
    }
}

/// What an issue's agent asks of the developer, for Delivery's order.
enum AgentAttention: Equatable {
    /// The agent stopped for an answer or a permission.
    case waiting
    /// The agent finished, or left a proposal: its work is to review.
    case finished

    static func of(session: AgentSession?, proposal: AgentProposal?, reviewed: Bool) -> AgentAttention? {
        if session?.state == .waiting { return .waiting }
        if proposal != nil { return .finished }
        if session?.state == .finished, !reviewed { return .finished }
        return nil
    }
}

/// The acceptance criteria of an issue, read from its description: the list under a heading that
/// names them, else the description's task list.
enum AcceptanceCriteria {
    private static let headings = ["acceptance", "criteria", "critère", "critere", "definition of done", "done when"]

    private static func item(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            // A bullet is its mark and a space: "**Bold**" is not one.
            guard text.dropFirst().first == " " else { return nil }
            text.removeFirst()
        } else if first.isNumber, let dot = text.firstIndex(where: { $0 == "." || $0 == ")" }), text[..<dot].allSatisfy(\.isNumber) {
            text = String(text[text.index(after: dot)...])
        } else {
            return nil
        }
        text = text.trimmingCharacters(in: .whitespaces)
        for box in ["[ ]", "[x]", "[X]"] where text.hasPrefix(box) { text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        return text.isEmpty ? nil : text
    }

    static func parse(_ description: String?) -> [String] {
        let lines = (description ?? "").components(separatedBy: .newlines)
        var under: [String] = []
        var inside = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let heading = trimmed.hasPrefix("#") || (trimmed.hasPrefix("**") && trimmed.hasSuffix("**")) || trimmed.hasSuffix(":")
            if heading, item(line) == nil {
                let lower = trimmed.lowercased()
                if inside, !under.isEmpty { break }
                inside = headings.contains { lower.contains($0) }
                continue
            }
            if inside, let found = item(line) { under.append(found) }
        }
        if !under.isEmpty { return under }
        // No heading names them: the task list, if the description has one.
        return lines.filter { $0.contains("[ ]") || $0.lowercased().contains("[x]") }.compactMap(item)
    }
}

/// The agents' proposals, for the whole app: one per issue (a new one replaces the last), the
/// criteria the developer ticked, the finished sessions already looked at. Memory only.
@MainActor
final class ProposalStore: ObservableObject {
    static let shared = ProposalStore()

    @Published private(set) var proposals: [String: AgentProposal] = [:]
    @Published private(set) var ticked: [String: Set<String>] = [:]
    /// Sessions whose finished turn the developer has looked at.
    @Published private(set) var reviewed: Set<String> = []

    init() {
        // Captures and Canary: the finished demo issue carries a proposal.
        if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_AGENT_SESSION"] == "canary",
           let made = AgentProposal(tool: .codex, arguments: [
            "issue": "APP-311", "summary": "The report can be exported as CSV from the toolbar; the file respects the active filters.",
            "not_verified": "A report over 50,000 rows.", "status": "In Review",
            "reply": "The CSV export is up on the preview: Export in the report's toolbar, filters included."],
                                    at: Date().addingTimeInterval(-6 * 60)) {
            proposals[Self.key(made.identifier)] = made
            return
        }
        guard ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_AGENT_SESSION"] == "finished",
              let demo = AgentProposal(tool: .claudeCode, arguments: [
                "issue": "APP-306", "summary": "The banner shows when the network drops and the last request is retried on reconnect.",
                "not_verified": "A connection that flaps every few seconds.", "status": "In Review",
                "reply": "The offline banner is up on the preview: it appears when the network drops and retries on reconnect."],
                                       at: Date().addingTimeInterval(-240)) else { return }
        proposals[Self.key(demo.identifier)] = demo
    }

    static func key(_ identifier: String) -> String { identifier.lowercased() }

    func proposal(for identifier: String) -> AgentProposal? { proposals[Self.key(identifier)] }

    func propose(_ proposal: AgentProposal) { proposals[Self.key(proposal.identifier)] = proposal }

    func update(_ identifier: String, _ change: (inout AgentProposal) -> Void) {
        guard var proposal = proposals[Self.key(identifier)] else { return }
        change(&proposal)
        proposals[Self.key(identifier)] = proposal
    }

    /// The whole proposal goes, with the criteria ticked for it.
    func dismiss(_ identifier: String) {
        proposals[Self.key(identifier)] = nil
        ticked[Self.key(identifier)] = nil
    }

    func toggle(_ criterion: String, of identifier: String) {
        var set = ticked[Self.key(identifier)] ?? []
        if !set.insert(criterion).inserted { set.remove(criterion) }
        ticked[Self.key(identifier)] = set
    }

    func isTicked(_ criterion: String, of identifier: String) -> Bool { ticked[Self.key(identifier)]?.contains(criterion) == true }

    func markReviewed(_ session: String) { reviewed.insert(session) }
}
