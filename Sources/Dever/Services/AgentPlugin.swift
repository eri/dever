import Foundation

/// Why a tool could not be connected or disconnected.
enum AgentPluginError: LocalizedError, Equatable {
    case toolNotFound(AgentTool)
    case refused(AgentTool, String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let tool): "\(tool.label) was not found on this Mac"
        case .refused(let tool, let message): "\(tool.label) refused: \(message)"
        }
    }
}

/// Dever's plugin for each coding agent: a handful of hooks that run one small command, which
/// tells Dever, on this Mac, that a session changed state. Dever writes the plugin into its own
/// folder and has the tool install it with the tool's own plugin command; it never edits the
/// tools' configuration files. "Disconnect" has the tool remove it.
enum AgentPlugin {
    static let name = "dever"
    static let version = "1.4.0"
    static let summary = "Tells Dever, on this Mac, when a session starts, works, waits for you and finishes, and lets the agent read the issue it works on."

    /// The command every hook runs.
    static var hook: URL { AgentBridge.folder.appendingPathComponent("dever-hook") }

    /// The command the agent runs to ask Dever something: the plugin's MCP server.
    static var context: URL { AgentBridge.folder.appendingPathComponent("dever-mcp") }

    /// The marketplace folder a tool installs the plugin from.
    static func marketplace(_ tool: AgentTool) -> URL {
        AgentBridge.folder.appendingPathComponent(tool == .claudeCode ? "claude-plugin" : "codex-plugin", isDirectory: true)
    }

    /// The moments each tool tells Dever about. Tool calls are among them so that a session that
    /// waited for a permission reads "working" again once it was given.
    static func events(_ tool: AgentTool) -> [String] {
        switch tool {
        case .claudeCode: ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "PostToolUse", "Stop", "SessionEnd"]
        case .codex: ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]
        }
    }

    /// Sends the hook's payload to Dever's listener and never holds the agent back: two seconds at
    /// most, no output, always success. Without Dever running it does nothing.
    static let hookScript = """
    #!/bin/sh
    # Dever: tells the Dever app, on this Mac only, that a coding agent's session changed state.
    # It posts the hook's payload to Dever's local listener and never fails the agent. At the end of
    # a turn Dever may answer with a reminder for the agent, printed here as the hook's output.
    address="${DEVER_BRIDGE:-$HOME/Library/Application Support/Dever/agent/bridge.json}"
    [ -r "$address" ] || exit 0
    port=$(sed -n 's/.*"port" *: *\\([0-9][0-9]*\\).*/\\1/p' "$address")
    token=$(sed -n 's/.*"token" *: *"\\([0-9a-f]*\\)".*/\\1/p' "$address")
    [ -n "$port" ] || exit 0
    answer=$(/usr/bin/curl -s -f -m 5 -X POST -H "Authorization: Bearer $token" \\
      -H "Content-Type: application/json" --data-binary @- "http://127.0.0.1:$port/hook/$1" 2>/dev/null)
    [ -n "$answer" ] && printf '%s\\n' "$answer"
    exit 0

    """

    /// The plugin's MCP server, as the agent sees it: a command speaking the protocol on its standard
    /// input and output. It only carries each request to Dever's listener and the answer back, so
    /// the agent needs no port and no token; without Dever running it answers that Dever is not there.
    static let contextScript = """
    #!/bin/sh
    # Dever: lets a coding agent ask the Dever app, on this Mac only, about the issue it works on.
    # Each request read here is carried to Dever's local listener, and the answer written back.
    address="${DEVER_BRIDGE:-$HOME/Library/Application Support/Dever/agent/bridge.json}"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      port=""; token=""
      if [ -r "$address" ]; then
        port=$(sed -n 's/.*"port" *: *\\([0-9][0-9]*\\).*/\\1/p' "$address")
        token=$(sed -n 's/.*"token" *: *"\\([0-9a-f]*\\)".*/\\1/p' "$address")
      fi
      if [ -n "$port" ] && answer=$(printf '%s' "$line" | /usr/bin/curl -s -f -m 60 -X POST -H "Authorization: Bearer $token" \\
          -H "Content-Type: application/json" --data-binary @- "http://127.0.0.1:$port/mcp/$1" 2>/dev/null); then
        [ -n "$answer" ] && printf '%s\\n' "$answer"
      else
        id=$(printf '%s' "$line" | awk 'match($0, /"id"[ \\t]*:[ \\t]*("[^"]*"|[0-9]+)/) { s = substr($0, RSTART, RLENGTH); sub(/^"id"[ \\t]*:[ \\t]*/, "", s); print s }')
        [ -n "$id" ] && printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32000,"message":"Dever is not running on this Mac"}}\\n' "$id"
      fi
    done
    exit 0

    """

    /// The skill that tells the agent when the tools help.
    static let skill = """
    ---
    name: dever
    description: Use when working on a Linear issue (an identifier like ENG-123, often with a brief that says "Work on ENG-123"), or when you need an issue's comments, the Slack thread it came from, or the state of its pull requests and checks. The dever tools read them from the Dever app on this Mac.
    ---

    # Dever

    Dever is the developer's project dashboard on this Mac. Its tools read what it knows about a Linear issue, and let you leave an account of your work. None of them changes anything in Linear, Slack or GitHub.

    - `get_issue`: the issue as Linear has it, with its comments, its parent, what blocks it and its links. Call it first: the brief you were given is short on purpose.
    - `get_thread`: the Slack thread the issue came from, when there is one. Decisions and constraints are often there and not in the issue.
    - `get_pull_requests`: the issue's pull requests, their checks and reviews, and how old that reading is.

    If you have a tool that reports your plan usage (in the Claude desktop app's Code sessions, `get_usage`), call it once at the start of a session on an issue and pass the figures to `report_usage`: percent used and reset time of the 5-hour window and of the weekly limit, and the plan's name. Skip it if you have no such tool.

    When you have finished the work on an issue, call `propose_update` once with a short account of what you did, what you did not verify, and, if it applies, the state the issue should move to and a reply for its Slack thread. It changes nothing: the developer sees it in Dever and applies, edits or dismisses it. Do not move the issue or post in Slack yourself unless the developer asked you to.

    Each takes the issue's identifier. If a tool says Dever is not running or that project context is switched off, carry on without it and say so in your answer; do not ask the developer to paste the content unless you are blocked.

    """

    /// The plugin's `.mcp.json`: one server, the command above with the tool's name.
    static func contextJSON(_ tool: AgentTool, command: String) -> String {
        "{\n  \"mcpServers\": {\n    \"\(name)\": {\"command\": \(quoted(command)), \"args\": [\(quoted(tool.rawValue))]}\n  }\n}\n"
    }

    /// The plugin's `hooks.json`: each event runs the hook command with the tool's name.
    static func hooksJSON(_ tool: AgentTool, command: String) -> String {
        let entries = events(tool).map { event in
            "    \"\(event)\": [{\"hooks\": [{\"type\": \"command\", \"command\": \(quoted(command + " " + tool.rawValue))}]}]"
        }
        return "{\n  \"hooks\": {\n" + entries.joined(separator: ",\n") + "\n  }\n}\n"
    }

    /// A string as a JSON string.
    static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    /// Every file of the plugin, by its path inside the marketplace folder.
    static func files(_ tool: AgentTool, hook: String, context: String) -> [String: String] {
        let command = "'" + hook.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let description = quoted(summary)
        switch tool {
        case .claudeCode:
            return [
                ".claude-plugin/marketplace.json": """
                {"name": "\(name)", "description": "Dever's plugin, written by the Dever app on this Mac.", "owner": {"name": "Dever"},
                 "plugins": [{"name": "\(name)", "source": "./\(name)", "description": \(description)}]}

                """,
                "\(name)/.claude-plugin/plugin.json": """
                {"name": "\(name)", "version": "\(version)", "description": \(description), "author": {"name": "Dever"}}

                """,
                "\(name)/hooks/hooks.json": hooksJSON(tool, command: command),
                "\(name)/.mcp.json": contextJSON(tool, command: context),
                "\(name)/skills/\(name)/SKILL.md": skill,
            ]
        case .codex:
            return [
                ".agents/plugins/marketplace.json": """
                {"name": "\(name)", "interface": {"displayName": "Dever"},
                 "plugins": [{"name": "\(name)", "source": {"source": "local", "path": "./plugins/\(name)"},
                              "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}, "category": "Productivity"}]}

                """,
                "plugins/\(name)/.codex-plugin/plugin.json": """
                {"name": "\(name)", "version": "\(version)", "description": \(description), "interface": {"displayName": "Dever"},
                 "skills": "./skills/", "mcpServers": "./.mcp.json"}

                """,
                "plugins/\(name)/hooks/hooks.json": hooksJSON(tool, command: command),
                "plugins/\(name)/.mcp.json": contextJSON(tool, command: context),
                "plugins/\(name)/skills/\(name)/SKILL.md": skill,
            ]
        }
    }

    private static func write(_ tool: AgentTool) throws {
        let files = FileManager.default
        try files.createDirectory(at: AgentBridge.folder, withIntermediateDirectories: true)
        for (script, text) in [(hook, hookScript), (context, contextScript)] {
            try text.write(to: script, atomically: true, encoding: .utf8)
            try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }
        let root = marketplace(tool)
        try? files.removeItem(at: root)
        for (path, text) in Self.files(tool, hook: hook.path, context: context.path) {
            let file = root.appendingPathComponent(path)
            try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    // MARK: The tools' own commands

    /// The tool's command-line binary: the one inside its desktop app, else where installers put it.
    static func binary(_ tool: AgentTool, codexApp: URL?) -> URL? {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        switch tool {
        case .codex:
            return CodexUsageReader.binary(app: codexApp)
        case .claudeCode:
            // The desktop app keeps Claude Code under its own folder, one folder per version: the newest.
            let bundled = home.appendingPathComponent("Library/Application Support/Claude/claude-code", isDirectory: true)
            let versions = ((try? files.contentsOfDirectory(atPath: bundled.path)) ?? [])
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in versions {
                let builds = (try? files.contentsOfDirectory(atPath: bundled.appendingPathComponent(version).path)) ?? []
                for build in builds {
                    let binary = bundled.appendingPathComponent("\(version)/\(build)/claude.app/Contents/MacOS/claude")
                    if files.isExecutableFile(atPath: binary.path) { return binary }
                }
            }
            return ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", home.appendingPathComponent(".local/bin/claude").path,
                    home.appendingPathComponent(".claude/local/claude").path]
                .first(where: files.isExecutableFile).map { URL(fileURLWithPath: $0) }
        }
    }

    /// The arguments of the tool's plugin command; Codex gets a valid approval policy for the run,
    /// since one it refuses in the user's configuration would stop it at start.
    static func arguments(_ tool: AgentTool, _ plugin: [String]) -> [String] {
        (tool == .codex ? ["-c", "approval_policy=\"on-request\""] : []) + ["plugin"] + plugin
    }

    private static func run(_ tool: AgentTool, binary: URL, _ plugin: [String]) -> (ok: Bool, said: String) {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments(tool, plugin)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (false, error.localizedDescription) }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: deadline)
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        deadline.cancel()
        return (process.terminationStatus == 0, said.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func lastLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).last.map(String.init) ?? "no reason given"
    }

    /// The version of Dever's plugin in the tool's own list of plugins; nil when it is not there.
    /// Codex says it on the plugin's line, Claude Code on the lines under it.
    static func installedVersion(_ tool: AgentTool, list: String) -> String? {
        let lines = list.split(whereSeparator: \.isNewline).map(String.init)
        guard let at = lines.firstIndex(where: { $0.contains("\(name)@\(name)") && (tool == .claudeCode || $0.contains("installed")) }) else { return nil }
        for line in lines[at...].prefix(tool == .claudeCode ? 4 : 1) {
            if let found = line.range(of: #"[0-9]+\.[0-9]+\.[0-9]+"#, options: .regularExpression) { return String(line[found]) }
        }
        return "unknown"
    }

    /// Whether the tool's own list of plugins has Dever's; remembered, for what a brief may promise.
    static func connected(_ tool: AgentTool, binary: URL) async -> Bool {
        let version = await Task.detached(priority: .utility) { () -> String? in
            let list = run(tool, binary: binary, ["list"])
            return list.ok ? installedVersion(tool, list: list.said) : nil
        }.value
        UserDefaults.standard.set(version != nil, forKey: AgentPreferences.followedKey(tool))
        return version != nil
    }

    /// A tool that has an older plugin of Dever's gets this one: the user connected it, and a newer
    /// Dever must not leave it with hooks or tools that no longer match. Tools not connected are left alone.
    static func updateIfOutdated(_ tool: AgentTool, binary: URL) async {
        let version = await Task.detached(priority: .utility) { () -> String? in
            let list = run(tool, binary: binary, ["list"])
            return list.ok ? installedVersion(tool, list: list.said) : nil
        }.value
        UserDefaults.standard.set(version != nil, forKey: AgentPreferences.followedKey(tool))
        guard let version, version != Self.version else { return }
        try? await connect(tool, binary: binary)
    }

    /// Writes the plugin and has the tool add the marketplace and install it.
    static func connect(_ tool: AgentTool, binary: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try write(tool)
            // What an earlier connect left is replaced: removing what is not there fails, harmlessly.
            _ = run(tool, binary: binary, [tool == .claudeCode ? "uninstall" : "remove", "\(name)@\(name)"])
            _ = run(tool, binary: binary, ["marketplace", "remove", name])
            let added = run(tool, binary: binary, ["marketplace", "add", marketplace(tool).path])
            guard added.ok else { throw AgentPluginError.refused(tool, lastLine(added.said)) }
            let installed = run(tool, binary: binary, [tool == .claudeCode ? "install" : "add", "\(name)@\(name)"])
            guard installed.ok else { throw AgentPluginError.refused(tool, lastLine(installed.said)) }
        }.value
    }

    /// Has the tool uninstall the plugin and forget the marketplace, then removes Dever's copy.
    static func disconnect(_ tool: AgentTool, binary: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let removed = run(tool, binary: binary, [tool == .claudeCode ? "uninstall" : "remove", "\(name)@\(name)"])
            _ = run(tool, binary: binary, ["marketplace", "remove", name])
            try? FileManager.default.removeItem(at: marketplace(tool))
            guard removed.ok else { throw AgentPluginError.refused(tool, lastLine(removed.said)) }
        }.value
    }
}
