import Foundation

/// Answers a coding agent's questions from what Dever holds: the Model Context Protocol requests
/// that reach the local bridge. Reads only. An agent whose "project context" is switched off in
/// Settings › Agents is offered no tool and refused if it calls one.
@MainActor
enum AgentContextServer {
    /// The answer to one request; nil for a notification, which has none.
    static func answer(_ body: Data, tool: AgentTool) async -> Data? {
        guard let (request, id) = AgentMCP.read(body) else {
            return AgentMCP.failure(code: -32700, "Not a JSON-RPC request", id: NSNull())
        }
        guard let id else { return nil }
        let allowed = AgentPreferences.context(tool)
        switch request {
        case .notification:
            return nil
        case .initialize(let version):
            return AgentMCP.result(["protocolVersion": version ?? AgentMCP.protocolVersion,
                                    "capabilities": ["tools": [String: Any]()],
                                    "serverInfo": ["name": "dever", "version": AgentPlugin.version],
                                    "instructions": AgentMCP.instructions], id: id)
        case .ping:
            return AgentMCP.result([:], id: id)
        case .list:
            return AgentMCP.result(AgentMCP.listing(allowed: allowed), id: id)
        case .unknown(let method):
            return AgentMCP.failure(code: -32601, "Dever does not know \(method)", id: id)
        case .call(let call):
            guard allowed else {
                return AgentMCP.text("Project context is switched off for \(tool.label) in Dever (Settings › Agents).", failed: true, id: id)
            }
            guard AgentMCP.tools.contains(where: { $0.name == call.tool }) else {
                return AgentMCP.failure(code: -32602, "Dever has no tool named \(call.tool)", id: id)
            }
            guard let identifier = call.issue?.trimmingCharacters(in: .whitespaces), !identifier.isEmpty else {
                return AgentMCP.text("Give the issue's identifier, like ENG-123.", failed: true, id: id)
            }
            if call.tool == "propose_update" {
                guard let proposal = AgentProposal(tool: tool, arguments: call.arguments, at: Date()) else {
                    return AgentMCP.text("Give a summary of what you did.", failed: true, id: id)
                }
                ProposalStore.shared.propose(proposal)
                return AgentMCP.text("Left for the developer in Dever, on \(proposal.identifier). Nothing was changed in Linear or Slack: they will apply, edit or dismiss it.", id: id)
            }
            do {
                return AgentMCP.text(try await run(call.tool, identifier: identifier), id: id)
            } catch {
                return AgentMCP.text("Dever could not read that: \(error.localizedDescription)", failed: true, id: id)
            }
        }
    }

    private struct Found {
        var issue: LinearIssue
        var project: Project?
        var readAt: Date?
    }

    /// The issue among the projects' issues Dever has read; the projects are read (within five
    /// minutes of their last reading) when it is not there yet.
    private static func find(_ identifier: String, app: AppState) async -> Found? {
        let store = IssueStore.shared
        func look() -> Found? {
            for project in app.projects {
                guard let linear = project.linear?.id, let known = store.projects[linear],
                      let issue = known.issues.first(where: { $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame }) else { continue }
                return Found(issue: issue, project: project, readAt: known.lastLoad)
            }
            return nil
        }
        if let found = look() { return found }
        for project in app.projects {
            if let linear = project.linear?.id { _ = try? await store.load(project: linear, maxAge: 300, app: app) }
        }
        return look()
    }

    private static func run(_ tool: String, identifier: String) async throws -> String {
        guard let app = AppState.current else { throw AppError.message("Dever is still starting") }
        guard let found = await find(identifier, app: app) else {
            return "Dever does not know \(identifier): it is not in the Linear projects Dever follows."
        }
        let now = Date()
        let detail = try await IssueStore.shared.detail(found.issue.id, updatedAt: found.issue.updatedAt, app: app)
        switch tool {
        case "get_issue":
            return AgentContextText.issue(detail, readAt: found.readAt, now: now)
        case "get_thread":
            let links = (detail.attachments?.nodes ?? []).compactMap { AgentContextText.slackLocation($0.url) }
            guard let link = links.first else { return "Linear links no Slack thread to \(detail.identifier)." }
            let parent = link.thread ?? link.ts
            let messages = try await app.withSlack { try await $0.thread(link.channel, threadTS: parent) }
            let slack = SlackStore.shared
            return AgentContextText.thread(messages, names: slack.users.mapValues(\.name), channel: slack.channelNames[link.channel], now: now)
        default:
            let repositories = found.project.map { app.repositories(for: $0) } ?? []
            let github = GitHubStore.shared
            var open: [GitHubPull] = [], merged: [GitHubPull] = []
            for repository in repositories {
                guard let known = github.repository(repository) else { continue }
                open += ProjectPullRequests(pulls: known.state.pulls, issues: [found.issue], wholeRepository: false).matches.map(\.pull)
                merged += ProjectPullRequests(pulls: known.merged, issues: [found.issue], wholeRepository: false).matches.map(\.pull)
            }
            return AgentContextText.pulls(identifier: detail.identifier, open: open, merged: merged,
                                          repositories: repositories.map { (name: $0, readAt: github.fetchedAt($0)) }, now: now)
        }
    }
}
