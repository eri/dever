import Foundation

/// The coding agents' sessions on this Mac, for the whole app: fed by the tools' hooks through the
/// local bridge, kept in memory only. Nothing is fetched and nothing is polled: a session is what
/// its last hook said, with its age. Empty after a relaunch until each session speaks again.
@MainActor
final class AgentStore: ObservableObject {
    static let shared = AgentStore()

    @Published private(set) var sessions: [String: AgentSession] = [:]

    init() {
        // Captures: DEVER_SNAPSHOT_AGENT_SESSION=working|waiting|finished|stale puts a made-up session
        // on the demo issue's branch.
        guard let scene = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_AGENT_SESSION"] else { return }
        let now = Date()
        var session = AgentSession(id: "demo", tool: .claudeCode, cwd: "/Users/sam/code/app", branch: "sam/app-306", state: .working, sentence: nil,
                                   since: now.addingTimeInterval(-12 * 60), heard: now.addingTimeInterval(-20))
        switch scene {
        case "waiting":
            session.state = .waiting
            session.since = now.addingTimeInterval(-3 * 60)
            session.sentence = "The retry needs a decision: back off for thirty seconds, or until the network returns?"
        case "finished":
            session.state = .finished
            session.since = now.addingTimeInterval(-4 * 60)
            session.sentence = "The banner shows offline and retries on reconnect. Not verified: a flaky connection."
        case "stale":
            session.heard = now.addingTimeInterval(-14 * 60)
        default: break
        }
        sessions[session.id] = session
    }

    /// The session to show for an issue: the one on its branch.
    func session(branch: String?) -> AgentSession? {
        AgentSession.current(for: branch, in: Array(sessions.values))
    }

    /// One hook call from a tool.
    func receive(_ event: AgentEvent, tool: AgentTool, at now: Date = Date()) {
        prune(at: now)
        let before = sessions[event.sessionID]
        var session = before?.applying(event, at: now) ?? AgentSession.starting(event, tool: tool, at: now)
        session.tool = tool
        sessions[event.sessionID] = session
        // The branch can change under a session: read again when it starts, is asked something, or finishes.
        let asks = ["SessionStart", "UserPromptSubmit", "Stop"].contains(event.hookEventName)
        if session.branch == nil || asks, let cwd = session.cwd { resolveBranch(of: event.sessionID, in: cwd) }
    }

    private func resolveBranch(of id: String, in cwd: String) {
        Task {
            let branch = await Task.detached(priority: .utility) { () -> String? in
                let folder = URL(fileURLWithPath: cwd, isDirectory: true)
                guard FileManager.default.fileExists(atPath: cwd) else { return nil }
                let answer = AgentLauncher.git(["rev-parse", "--abbrev-ref", "HEAD"], in: folder, timeout: 5)
                return answer.status == 0 && !answer.output.isEmpty && answer.output != "HEAD" ? answer.output : nil
            }.value
            if var session = sessions[id], session.branch != branch, branch != nil || session.branch == nil {
                session.branch = branch
                sessions[id] = session
            }
        }
    }

    /// Closed sessions leave after ten minutes; anything silent for a day is forgotten.
    private func prune(at now: Date) {
        sessions = sessions.filter { _, session in
            let silent = now.timeIntervalSince(session.heard)
            return session.state == .ended ? silent < 600 : silent < 86_400
        }
    }
}
