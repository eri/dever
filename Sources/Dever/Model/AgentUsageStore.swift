import Foundation

/// The agents' plan usage, for the whole app: one entry per tool, in memory only. Read when a
/// surface that shows it opens and the value is older than its budget; never polled in the
/// background (a reading costs a child process and two seconds whether or not anything changed).
@MainActor
final class AgentUsageStore: ObservableObject {
    static let shared = AgentUsageStore()

    @Published private(set) var entries: [AgentTool: AgentUsageEntry] = [:]
    /// Tools a start from Dever just used: their figure moved, so the next opening reads again.
    private var dirty: Set<AgentTool> = []

    init() {
        // Captures: DEVER_SNAPSHOT_AGENT_USAGE=1 shows a made-up reading instead of asking the tool.
        if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_AGENT_USAGE"] == "1" {
            let now = Date()
            // Claude Code, as its agent would pass it on (report_usage): less room than Codex.
            entries[.claudeCode] = .init(usage: AgentUsage(
                windows: [.init(usedPercent: 74, minutes: 300, resetsAt: now.addingTimeInterval(3600 + 1200)),
                          .init(usedPercent: 45, minutes: 10_080, resetsAt: now.addingTimeInterval(3 * 86_400))],
                plan: "Team", limitReached: false, readAt: now.addingTimeInterval(-2 * 60)), checkedAt: now)
            entries[.codex] = .init(usage: AgentUsage(
                windows: [.init(usedPercent: 38, minutes: 300, resetsAt: now.addingTimeInterval(2 * 3600 + 600)),
                          .init(usedPercent: 20, minutes: 10_080, resetsAt: now.addingTimeInterval(4 * 86_400))],
                plan: "team", limitReached: false, readAt: now), checkedAt: now)
        }
    }

    private var demo: Bool { ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_AGENT_USAGE"] == "1" }

    /// Reads the tools whose usage can be read, unless the value is younger than `maxAge`.
    func refresh(maxAge: TimeInterval = AgentUsage.fresh) async {
        guard !demo else { return }
        for tool in AgentTool.allCases where tool.usageIsReadable { await refresh(tool, maxAge: maxAge) }
    }

    private func refresh(_ tool: AgentTool, maxAge: TimeInterval) async {
        var entry = entries[tool] ?? .init()
        if entry.loading { return }
        if let checked = entry.checkedAt, !dirty.contains(tool), Date().timeIntervalSince(checked) < maxAge { return }
        dirty.remove(tool)
        guard tool == .codex else { return }
        guard let binary = CodexUsageReader.binary(app: AgentApps.app(.codex)) else {
            entries[tool] = .init(usage: nil, problem: CodexUsageError.notInstalled.localizedDescription, checkedAt: Date())
            return
        }
        entry.loading = true
        entries[tool] = entry
        do {
            entries[tool] = .init(usage: try await CodexUsageReader.read(binary: binary), checkedAt: Date())
        } catch CodexUsageError.noPlan {
            // Not a failure: there is no window to read, and the old one no longer applies.
            entries[tool] = .init(usage: nil, problem: CodexUsageError.noPlan.localizedDescription, checkedAt: Date())
        } catch {
            // The last value stays, with its age; the reason sits beside it.
            entries[tool] = .init(usage: entry.usage, problem: error.localizedDescription,
                                  detail: (error as? CodexUsageError)?.detail, checkedAt: Date())
        }
    }

    /// A reading an agent passed on (`report_usage`): kept like one Dever made, with its age.
    func receive(_ usage: AgentUsage, for tool: AgentTool) {
        entries[tool] = .init(usage: usage, checkedAt: usage.readAt)
    }

    /// A start from Dever changes the figure: the next opening reads again.
    func markDirty(_ tool: AgentTool) { dirty.insert(tool) }
}
