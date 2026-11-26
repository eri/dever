import Foundation

// What a coding agent can ask Dever about the issue it works on (docs/agents-integration.md,
// phase 3): the issue as Linear has it, the Slack thread it came from, its pull requests and
// checks. Read only, served from the stores Dever already keeps, and said with the age of what
// is returned. The agent asks; Dever never sends anything on its own.

/// The Model Context Protocol, as much as a read-only tool server needs: JSON-RPC over the local
/// bridge, one request, one answer.
enum AgentMCP {
    static let protocolVersion = "2025-06-18"

    struct Tool {
        var name: String
        var description: String
        /// The description of `issue`, the argument every tool takes.
        var argument: String
        /// The other arguments, with whether each is required. All are strings.
        var more: [(name: String, description: String, required: Bool)] = []
        /// A tool that only reads.
        var readOnly = true
    }

    static let tools: [Tool] = [
        .init(name: "get_issue",
              description: "The Linear issue as Dever has it: state, assignee, priority, branch, description, parent and sub-issues, what blocks it, its links and its comments.",
              argument: "The issue's identifier, like ENG-123."),
        .init(name: "get_thread",
              description: "The Slack thread the issue came from, when Linear links one: who said what, oldest first. Use it for the context and the decisions that are not in the issue.",
              argument: "The issue's identifier, like ENG-123."),
        .init(name: "get_pull_requests",
              description: "The pull requests of the issue as Dever last read them: number, state, branch, checks, review verdicts, and how old that reading is.",
              argument: "The issue's identifier, like ENG-123."),
        .init(name: "propose_update",
              description: "Tell the developer what you did on the issue, in Dever, when you have finished. It changes nothing: the developer reads your account and applies, edits or dismisses what you suggest (moving the issue, answering the Slack thread).",
              argument: "The issue's identifier, like ENG-123.",
              more: [("summary", "What you did, in one to three sentences.", true),
                     ("not_verified", "What you did not or could not verify, if anything.", false),
                     ("status", "The workflow state you suggest for the issue, by its name (for example \"In Review\"), if it should move.", false),
                     ("reply", "A short reply to post in the issue's Slack thread, in the thread's language, if the people there should know.", false)],
              readOnly: false),
        .init(name: "report_usage",
              description: "Pass Dever what is left of your plan, as your own usage tool reports it (in the Claude desktop app's Code sessions, get_usage). Dever shows it to the developer with its age and uses it to suggest the agent with the most room. Call it once, at the start of a session on an issue.",
              argument: "The issue you work on, like ENG-123 (or an empty string).",
              more: [("five_hour_used", "Percent of the 5-hour window used, a number like 38.", false),
                     ("five_hour_resets", "When the 5-hour window resets, ISO 8601 like 2026-11-26T14:10:00Z.", false),
                     ("week_used", "Percent of the weekly limit (all models) used, a number like 20.", false),
                     ("week_resets", "When the weekly limit resets, ISO 8601.", false),
                     ("plan", "The plan's name, as the tool says it.", false)],
              readOnly: false),
    ]

    static let instructions = "Dever is the developer's project dashboard on this Mac. These tools read what it knows about a Linear issue: the issue itself, the Slack thread it came from, its pull requests and checks. propose_update leaves your account of the work for the developer to act on. None of them changes anything in Linear, Slack or GitHub."

    /// The identifier asked for in a `tools/call`.
    struct Call: Equatable {
        var tool: String
        /// The arguments that are strings, by name.
        var arguments: [String: String] = [:]
        var issue: String? { arguments["issue"] }
    }

    /// What a request asks, read without doing anything.
    enum Request: Equatable {
        case initialize(version: String?)
        case ping
        case list
        case call(Call)
        case notification
        case unknown(String)
    }

    /// The request and its id (as JSON text, to send back as it came); nil when the body is not JSON-RPC.
    static func read(_ body: Data) -> (request: Request, id: Any?)? {
        guard let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = message["method"] as? String else { return nil }
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]
        guard id != nil, !(id is NSNull) else { return (.notification, nil) }
        switch method {
        case "initialize": return (.initialize(version: params["protocolVersion"] as? String), id)
        case "ping": return (.ping, id)
        case "tools/list": return (.list, id)
        case "tools/call":
            // Strings, and numbers as their text (a percent may come as either).
            let arguments = (params["arguments"] as? [String: Any] ?? [:]).compactMapValues { value -> String? in
                if let text = value as? String { return text }
                if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
                return nil
            }
            return (.call(.init(tool: params["name"] as? String ?? "", arguments: arguments)), id)
        default: return (.unknown(method), id)
        }
    }

    static func result(_ value: [String: Any], id: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": value])) ?? Data()
    }

    static func failure(code: Int, _ message: String, id: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])) ?? Data()
    }

    /// A tool's answer: text for the agent, flagged when it is a refusal or a failure.
    static func text(_ text: String, failed: Bool = false, id: Any) -> Data {
        result(["content": [["type": "text", "text": text]], "isError": failed], id: id)
    }

    static func listing(allowed: Bool) -> [String: Any] {
        ["tools": allowed ? tools.map { tool in
            var properties: [String: Any] = ["issue": ["type": "string", "description": tool.argument]]
            for argument in tool.more { properties[argument.name] = ["type": "string", "description": argument.description] }
            return ["name": tool.name, "description": tool.description,
                    "inputSchema": ["type": "object", "properties": properties,
                                    "required": ["issue"] + tool.more.filter(\.required).map(\.name)] as [String: Any],
                    "annotations": ["readOnlyHint": tool.readOnly]] as [String: Any]
        } : []]
    }
}

/// The answers, as text an agent reads. Pure: what to say of an issue, a thread, pull requests.
enum AgentContextText {
    static func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "at an unknown time" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 90 { return "just now" }
        return "\(AgentSession.span(seconds)) ago"
    }

    static func issue(_ detail: LinearIssueDetail, readAt: Date?, now: Date) -> String {
        var lines = ["\(detail.identifier): \(detail.title)", "State: \(detail.state.name)"]
        lines.append("Assignee: \(detail.assignee?.name ?? "nobody")")
        lines.append("Priority: \(detail.priorityLabel)")
        if !detail.labelList.isEmpty { lines.append("Labels: \(detail.labelList.map(\.name).joined(separator: ", "))") }
        if let due = detail.dueDate { lines.append("Due: \(due)") }
        if let branch = detail.branchName, !branch.isEmpty { lines.append("Branch: \(branch)") }
        lines.append("URL: \(detail.url)")
        if let parent = detail.parent { lines.append("Part of: \(parent.identifier) \(parent.title) (\(parent.state.name))") }
        func list(_ title: String, _ briefs: [LinearIssueDetail.Brief]) {
            guard !briefs.isEmpty else { return }
            lines.append("\(title):")
            lines += briefs.map { "- \($0.identifier) \($0.title) (\($0.state.name))" }
        }
        list("Sub-issues", detail.subIssues)
        list("Blocked by", detail.blockedBy)
        list("Blocks", detail.blocks)
        list("Related", detail.related)
        let links = (detail.attachments?.nodes ?? []).map { [$0.title, $0.url].compactMap { $0 }.joined(separator: " ") }
        if !links.isEmpty {
            lines.append("Links:")
            lines += links.map { "- \($0)" }
        }
        lines.append("")
        lines.append("Description:")
        let description = (detail.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(description.isEmpty ? "(none)" : description)
        let comments = detail.thread
        if !comments.isEmpty {
            lines.append("")
            lines.append("Comments (\(comments.count), oldest first):")
            for comment in comments {
                lines.append("[\(comment.createdAt.prefix(16).replacingOccurrences(of: "T", with: " "))] \(comment.authorName): \(comment.body)")
            }
        }
        lines.append("")
        lines.append("(Read from Linear \(age(readAt, now: now)).)")
        return lines.joined(separator: "\n")
    }

    /// A Slack message's channel and time, from its link: `…/archives/C123/p1700000000123456`
    /// (a reply's link carries its parent in `thread_ts`).
    static func slackLocation(_ url: String) -> (channel: String, ts: String, thread: String?)? {
        guard let components = URLComponents(string: url), components.host?.hasSuffix("slack.com") == true else { return nil }
        let parts = components.path.split(separator: "/")
        guard let archives = parts.firstIndex(of: "archives"), parts.count > archives + 2 else { return nil }
        let raw = parts[archives + 2]
        guard raw.hasPrefix("p"), raw.count > 7, raw.dropFirst().allSatisfy(\.isNumber) else { return nil }
        let digits = raw.dropFirst()
        let ts = "\(digits.dropLast(6)).\(digits.suffix(6))"
        return (String(parts[archives + 1]), ts, components.queryItems?.first { $0.name == "thread_ts" }?.value)
    }

    static func thread(_ messages: [SlackMessage], names: [String: String], channel: String?, now: Date) -> String {
        guard !messages.isEmpty else { return "The thread is empty." }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = ["Slack thread\(channel.map { " in #\($0)" } ?? "") (\(messages.count) messages, oldest first):"]
        for message in messages.sorted(by: { $0.ts < $1.ts }) {
            let who = message.user.flatMap { names[$0] } ?? "someone"
            lines.append("[\(formatter.string(from: message.date))] \(who): \(mentions(message.text ?? "", names: names))")
        }
        lines.append("")
        lines.append("(Read from Slack just now.)")
        return lines.joined(separator: "\n")
    }

    /// `<@U123>` as the person's name.
    static func mentions(_ text: String, names: [String: String]) -> String {
        var out = text
        for (id, name) in names where out.contains("<@\(id)>") { out = out.replacingOccurrences(of: "<@\(id)>", with: "@\(name)") }
        return out
    }

    static func checks(_ rollup: String?) -> String {
        switch rollup {
        case "SUCCESS": "checks pass"
        case "FAILURE", "ERROR": "checks FAIL"
        case "PENDING", "EXPECTED": "checks running"
        default: "no checks"
        }
    }

    static func pulls(identifier: String, open: [GitHubPull], merged: [GitHubPull], repositories: [(name: String, readAt: Date?)], now: Date) -> String {
        guard !repositories.isEmpty else { return "The project of \(identifier) follows no repository in Dever." }
        var lines: [String] = []
        if open.isEmpty && merged.isEmpty {
            lines.append("No pull request found for \(identifier) (matched by its branch, its identifier in the branch or the title, or Linear's link).")
        }
        for pull in open {
            var facts = [pull.draft == true ? "draft" : "open", "branch \(pull.head.ref)", "by \(pull.user.login)", checks(pull.checks)]
            let verdicts = pull.verdicts ?? []
            if verdicts.contains("CHANGES_REQUESTED") { facts.append("changes requested") }
            else if verdicts.contains("APPROVED") { facts.append("approved") }
            if let asked = pull.requested_reviewers, !asked.isEmpty { facts.append("review asked of \(asked.map(\.login).joined(separator: ", "))") }
            lines.append("#\(pull.number) \(pull.title): \(facts.joined(separator: ", "))\n  \(pull.html_url)")
        }
        for pull in merged {
            lines.append("#\(pull.number) \(pull.title): merged \(pull.merged_at?.prefix(10) ?? ""), branch \(pull.head.ref)\n  \(pull.html_url)")
        }
        lines.append("")
        for repository in repositories {
            lines.append(repository.readAt == nil ? "(\(repository.name): not read by Dever yet; open the project in Dever.)"
                                                  : "(\(repository.name): read from GitHub \(age(repository.readAt, now: now)).)")
        }
        return lines.joined(separator: "\n")
    }
}
