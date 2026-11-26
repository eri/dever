import Foundation

// A coding agent's session as its hooks describe it (docs/agents-integration.md, phase 2): the
// tools tell Dever, on this Mac, when a session starts, works, waits for the user and finishes.
// Dever keeps the state, its age and the agent's last sentence, in memory, and nothing else of
// what a hook carries.

/// What Dever keeps of one hook call. Everything else in the payload (the prompt, a tool's input
/// and output) is not decoded, so it is dropped on arrival.
struct AgentEvent: Decodable, Equatable {
    var hookEventName: String
    var sessionID: String
    var cwd: String?
    var lastAssistantMessage: String?
    var message: String?
    var notificationType: String?
    var toolName: String?
    /// On Stop: the turn was already continued by a Stop hook (no second reminder).
    var stopHookActive: Bool?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name", sessionID = "session_id", cwd
        case lastAssistantMessage = "last_assistant_message", message
        case notificationType = "notification_type", toolName = "tool_name", stopHookActive = "stop_hook_active"
    }
}

/// One session of a coding agent on this Mac.
struct AgentSession: Equatable, Identifiable {
    enum State: Equatable {
        /// Open, nothing asked yet (a brief filled in and not sent).
        case ready
        case working
        /// The agent stopped for the user: a permission, a question.
        case waiting
        /// The agent ended its turn.
        case finished
        /// The session was closed.
        case ended
    }

    var id: String
    var tool: AgentTool
    var cwd: String?
    /// The branch checked out in `cwd`: what ties the session to an issue.
    var branch: String?
    var state: State
    /// The agent's last sentence, or what it waits for. Memory only.
    var sentence: String?
    /// When the state last changed, and when a hook was last heard.
    var since: Date
    var heard: Date

    /// A working session that has said nothing for this long is drawn as old: a killed terminal
    /// sends no goodbye, so Dever only knows what the last hook said.
    static let quiet: TimeInterval = 600

    func stale(at now: Date) -> Bool { state == .working && now.timeIntervalSince(heard) > Self.quiet }

    /// The session after a hook call.
    func applying(_ event: AgentEvent, at now: Date) -> AgentSession {
        var next = self
        next.heard = now
        if let cwd = event.cwd, !cwd.isEmpty { next.cwd = cwd }
        func move(_ state: State, sentence: String?) {
            if next.state != state { next.since = now }
            next.state = state
            next.sentence = sentence
        }
        switch event.hookEventName {
        case "SessionStart":
            // A resumed session that had finished stays finished until something is asked of it.
            if state == .ended || state == .ready { move(.ready, sentence: nil) }
        case "UserPromptSubmit":
            move(.working, sentence: nil)
        case "PreToolUse", "PostToolUse":
            // A tool ran: whatever was waited for was answered.
            if state != .finished { move(.working, sentence: nil) }
        case "PermissionRequest":
            move(.waiting, sentence: event.toolName.map { "Asks to use \($0)" })
        case "Notification":
            // Only the notices that mean "your turn"; an idle reminder after a finished turn changes nothing.
            if ["permission_prompt", "agent_needs_input", "elicitation_dialog"].contains(event.notificationType ?? "") {
                move(.waiting, sentence: Self.last(event.message) ?? next.sentence)
            }
        case "Stop":
            move(.finished, sentence: Self.last(event.lastAssistantMessage))
        case "SessionEnd":
            if next.state != .ended { next.since = now }
            next.state = .ended
        default:
            break
        }
        return next
    }

    /// A new session, from its first hook call.
    static func starting(_ event: AgentEvent, tool: AgentTool, at now: Date) -> AgentSession {
        AgentSession(id: event.sessionID, tool: tool, cwd: event.cwd, branch: nil, state: .ready, sentence: nil, since: now, heard: now)
            .applying(event, at: now)
    }

    /// The end of what the agent said: its last paragraph, on one line, cut at 220 characters.
    static func last(_ text: String?) -> String? {
        guard let text else { return nil }
        let paragraphs = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let last = paragraphs.last else { return nil }
        let line = last.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > 220 ? String(line.prefix(219)) + "…" : line
    }

    /// The state in words with its age: "Working · 12 min", "Waiting for you · 3 min",
    /// "Finished 4 min ago", and "Working · last heard 14 min ago" once it is old.
    func words(at now: Date) -> String {
        switch state {
        case .ready: return "Open, not started"
        case .working:
            return stale(at: now) ? "Working · last heard \(Self.span(now.timeIntervalSince(heard))) ago"
                                  : "Working · \(Self.span(now.timeIntervalSince(since)))"
        case .waiting: return "Waiting for you · \(Self.span(now.timeIntervalSince(since)))"
        case .finished: return "Finished \(Self.span(now.timeIntervalSince(since))) ago"
        case .ended: return "Session closed"
        }
    }

    static func span(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "under a min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours) h" : "\(hours / 24) d"
    }

    /// The link that brings the session forward in its tool. Codex documents its own; the Claude
    /// app's is read from the app (docs/agents-integration.md, section 2.5).
    var link: URL? {
        switch tool {
        case .codex: URL(string: "codex://threads/\(id)")
        case .claudeCode: URL(string: "claude://resume?session=\(id)")
        }
    }
}

extension AgentSession {
    /// Among sessions, the one an issue's line shows: on its branch, not closed, the one that
    /// needs the user first, then the most recently heard.
    static func current(for branch: String?, in sessions: [AgentSession]) -> AgentSession? {
        guard let branch = branch?.lowercased(), !branch.isEmpty else { return nil }
        func rank(_ state: State) -> Int {
            switch state {
            case .waiting: 0
            case .working: 1
            case .finished: 2
            case .ready: 3
            case .ended: 4
            }
        }
        return sessions.filter { $0.branch?.lowercased() == branch && $0.state != .ended }
            .min { (rank($0.state), -$0.heard.timeIntervalSince1970) < (rank($1.state), -$1.heard.timeIntervalSince1970) }
    }
}

/// One HTTP request to the local bridge, read from the bytes received so far.
enum BridgeRequest: Equatable {
    case incomplete
    case malformed
    case request(method: String, path: String, bearer: String?, body: Data)

    static func parse(_ data: Data) -> BridgeRequest {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return data.count > 16_384 ? .malformed : .incomplete }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return .malformed }
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return .malformed }
        var length = 0
        var bearer: String?
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "content-length" { length = Int(value) ?? -1 }
            if name == "authorization", value.lowercased().hasPrefix("bearer ") { bearer = String(value.dropFirst(7)) }
        }
        guard length >= 0 else { return .malformed }
        let body = data[end.upperBound...]
        guard body.count >= length else { return .incomplete }
        return .request(method: String(first[0]), path: String(first[1]), bearer: bearer, body: Data(body.prefix(length)))
    }
}

/// The reminder a Stop hook gives back to the agent (docs/agents-integration.md, phase 4): once per
/// session, when the agent ends a turn on a branch Dever knows as an issue's, with Dever's tools at
/// hand and no account of its work left yet. Both tools take `{"decision": "block", "reason": …}` on
/// a Stop hook's output as "continue, with this as the next instruction".
enum AgentReminder {
    /// The reason the agent reads; it may well not be finished, and is told to just stop then.
    static func reason(identifier: String) -> String {
        "Dever: if you have finished the work on \(identifier), call the dever tool propose_update once, with a short summary, "
            + "what you did not verify, and, if it applies, the workflow state the issue should move to and a reply for its Slack thread. "
            + "It changes nothing: the developer applies it. If the work is not finished, or you are waiting for the developer, "
            + "do not call it and just end your turn."
    }

    /// The Stop hook's output.
    static func output(identifier: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["decision": "block", "reason": reason(identifier: identifier)])) ?? Data()
    }

    /// Whether to remind: a Stop not already continued, the tools on for this agent, an issue known
    /// for the branch, no reminder yet in this session, and no proposal left since it began.
    static func needed(event: AgentEvent, contextOn: Bool, issue: String?, reminded: Bool,
                       proposalAt: Date?, sessionStart: Date?) -> Bool {
        guard event.hookEventName == "Stop", event.stopHookActive != true, contextOn, issue != nil, !reminded else { return false }
        if let proposalAt { return proposalAt < (sessionStart ?? .distantPast) }
        return true
    }
}
