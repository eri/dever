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
    static let version = "1.0.0"
    static let summary = "Tells Dever, on this Mac, when a session starts, works, waits for you and finishes."

    /// The command every hook runs.
    static var hook: URL { AgentBridge.folder.appendingPathComponent("dever-hook") }

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
    # It posts the hook's payload to Dever's local listener and never blocks or fails the agent.
    address="${DEVER_BRIDGE:-$HOME/Library/Application Support/Dever/agent/bridge.json}"
    [ -r "$address" ] || exit 0
    port=$(sed -n 's/.*"port" *: *\\([0-9][0-9]*\\).*/\\1/p' "$address")
    token=$(sed -n 's/.*"token" *: *"\\([0-9a-f]*\\)".*/\\1/p' "$address")
    [ -n "$port" ] || exit 0
    /usr/bin/curl -s -m 2 -o /dev/null -X POST -H "Authorization: Bearer $token" \\
      -H "Content-Type: application/json" --data-binary @- "http://127.0.0.1:$port/hook/$1" 2>/dev/null
    exit 0

    """

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
    static func files(_ tool: AgentTool, hook: String) -> [String: String] {
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
            ]
        case .codex:
            return [
                ".agents/plugins/marketplace.json": """
                {"name": "\(name)", "interface": {"displayName": "Dever"},
                 "plugins": [{"name": "\(name)", "source": {"source": "local", "path": "./plugins/\(name)"},
                              "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}, "category": "Productivity"}]}

                """,
                "plugins/\(name)/.codex-plugin/plugin.json": """
                {"name": "\(name)", "version": "\(version)", "description": \(description), "interface": {"displayName": "Dever"}}

                """,
                "plugins/\(name)/hooks/hooks.json": hooksJSON(tool, command: command),
            ]
        }
    }

    private static func write(_ tool: AgentTool) throws {
        let files = FileManager.default
        try files.createDirectory(at: AgentBridge.folder, withIntermediateDirectories: true)
        try hookScript.write(to: hook, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        let root = marketplace(tool)
        try? files.removeItem(at: root)
        for (path, text) in Self.files(tool, hook: hook.path) {
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

    /// Whether the tool's own list of plugins has Dever's.
    static func connected(_ tool: AgentTool, binary: URL) async -> Bool {
        await Task.detached(priority: .utility) {
            let list = run(tool, binary: binary, ["list"])
            return list.ok && list.said.split(whereSeparator: \.isNewline).contains { line in
                line.contains("\(name)@\(name)") && (tool == .claudeCode || line.contains("installed"))
            }
        }.value
    }

    /// Writes the plugin and has the tool add the marketplace and install it.
    static func connect(_ tool: AgentTool, binary: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try write(tool)
            // A marketplace left from an earlier connect is replaced: removing one that is not there fails, harmlessly.
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
