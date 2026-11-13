import Foundation

// Starting a coding agent on an issue (docs/agents-integration.md, phase 1): which tool, where it
// opens, where each repository's clone is on this Mac, the worktree on the issue's branch, the
// brief, and the link that opens the tool on that folder with the brief filled in, not sent.
// Everything here is derived without the network and without a process, so it is tested.

/// The coding agents Dever can start.
enum AgentTool: String, CaseIterable, Identifiable {
    case claudeCode, codex
    var id: String { rawValue }
    var label: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// Where a tool opens: its desktop app, or a terminal.
enum AgentSurface: String, CaseIterable, Identifiable {
    case app, terminal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .app: "Desktop app"
        case .terminal: "Terminal"
        }
    }
}

/// Settings › Agents, in UserDefaults: where each repository is cloned on this Mac, and where each tool opens.
enum AgentPreferences {
    /// Repository ("owner/name", lowercased) to the path of its clone. Clones live wherever the
    /// user keeps them, so each is asked for once, at the first start on that repository.
    static let clonesKey = "agentClones"
    static func surfaceKey(_ tool: AgentTool) -> String { "agentSurface.\(tool.rawValue)" }
    static let lastToolKey = "agentLastTool"

    static var clones: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: clonesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: clonesKey) }
    }

    /// The clone of a repository, when it was given and is still there.
    static func clone(of repository: String, in clones: [String: String] = AgentPreferences.clones) -> URL? {
        guard let path = clones[repository.lowercased()], FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func setClone(_ folder: URL?, for repository: String) {
        var all = clones
        all[repository.lowercased()] = folder?.path
        clones = all
    }

    static func surface(_ tool: AgentTool) -> AgentSurface {
        UserDefaults.standard.string(forKey: surfaceKey(tool)).flatMap(AgentSurface.init(rawValue:)) ?? .app
    }

    /// The tool started last, offered first next time.
    static var lastTool: AgentTool {
        get { UserDefaults.standard.string(forKey: lastToolKey).flatMap(AgentTool.init(rawValue:)) ?? .claudeCode }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lastToolKey) }
    }
}

/// Tells which GitHub repository a folder is a clone of, by its `origin` remote, and finds the
/// clones under a folder ("Find my clones in…").
enum CloneFinder {
    /// The repository ("owner/name", lowercased) a folder is a clone of; nil when it is not a clone
    /// (no `.git` directory: a plain folder, or a worktree) or has no GitHub-style `origin`.
    static func repository(of folder: URL) -> String? {
        var isDirectory: ObjCBool = false
        let git = folder.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: git.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let config = try? String(contentsOf: git.appendingPathComponent("config"), encoding: .utf8) else { return nil }
        return originURL(inConfig: config).flatMap(slug(fromRemote:))
    }

    /// "owner/name", lowercased, from a git remote URL; nil when it is not a GitHub-style remote.
    /// Reads `git@host:owner/name.git`, `https://host/owner/name(.git)` and `ssh://git@host/owner/name`.
    static func slug(fromRemote remote: String) -> String? {
        var text = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        let path: Substring
        if let scheme = text.range(of: "://") {
            let rest = text[scheme.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            path = rest[rest.index(after: slash)...]
        } else if let colon = text.firstIndex(of: ":"), text.contains("@") {
            path = text[text.index(after: colon)...]
        } else {
            return nil
        }
        let parts = path.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return "\(parts[0])/\(parts[1])".lowercased()
    }

    /// The `origin` URL in the text of a `.git/config`.
    static func originURL(inConfig config: String) -> String? {
        var inOrigin = false
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line.replacingOccurrences(of: " ", with: "") == "[remote\"origin\"]"
            } else if inOrigin, line.hasPrefix("url"), let equals = line.firstIndex(of: "=") {
                return line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Folders never worth entering: dependencies, build output, and Dever's own worktrees.
    static let skipped: Set<String> = ["node_modules", "build", "dist", "vendor", "Pods", "DerivedData", "target"]

    /// Every clone under `root`, by slug. A clone is a folder whose `.git` is a directory (a worktree's
    /// is a file, so worktrees are not taken for clones); the search stops at a clone and goes
    /// `depth` folders deep at most. The shallowest clone of a repository wins.
    static func clones(under root: URL, depth: Int = 3, files: FileManager = .default) -> [String: URL] {
        var found: [String: URL] = [:]
        var level = [root]
        for _ in 0...depth {
            var next: [URL] = []
            for folder in level {
                if files.fileExists(atPath: folder.appendingPathComponent(".git").path) {
                    if let slug = repository(of: folder), found[slug] == nil { found[slug] = folder }
                    continue
                }
                let children = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                               options: [.skipsHiddenFiles])) ?? []
                next += children.filter {
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !skipped.contains($0.lastPathComponent)
                }.sorted { $0.path < $1.path }
            }
            level = next
            if level.isEmpty { break }
        }
        return found
    }
}

/// The worktree an agent works in: one folder per issue branch, beside the clone it comes from.
enum AgentWorktree {
    /// `<the clone's parent>/.dever/worktrees/<the clone's folder name>/<branch, slashes as dashes>`:
    /// next to the clone, so on its volume and easy to find; hidden, so a search for clones never enters it.
    static func folder(clone: URL, branch: String) -> URL {
        clone.deletingLastPathComponent().appendingPathComponent(".dever/worktrees", isDirectory: true)
            .appendingPathComponent(clone.lastPathComponent, isDirectory: true)
            .appendingPathComponent(folderName(branch), isDirectory: true)
    }

    /// A branch name as one path component.
    static func folderName(_ branch: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let name = String(branch.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return name.isEmpty ? "branch" : name
    }

    /// Where `branch` is already checked out, from `git worktree list --porcelain`: the clone itself
    /// or any worktree, whoever made it. Git refuses a second checkout of a branch, so that folder is used.
    static func checkedOut(branch: String, inPorcelain text: String) -> String? {
        var path: String?
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("worktree ") { path = String(line.dropFirst("worktree ".count)) }
            else if line == "branch refs/heads/\(branch)" { return path }
        }
        return nil
    }

    /// The `git worktree add` arguments for the three cases: the branch exists here, exists on
    /// `origin` only, or is new (cut from `base`, the default branch).
    static func addArguments(folder: URL, branch: String, existsLocally: Bool, existsOnOrigin: Bool, base: String) -> [String] {
        if existsLocally { return ["worktree", "add", folder.path, branch] }
        if existsOnOrigin { return ["worktree", "add", "--track", "-b", branch, folder.path, "origin/\(branch)"] }
        return ["worktree", "add", "-b", branch, folder.path, base]
    }
}

/// The text an agent starts from. Short on purpose: the issue as Linear has it, its branch, its links.
enum AgentBrief {
    /// The Claude app cuts a link's prompt at 14,336 characters; stay well under for every tool.
    static let limit = 12_000

    static func text(identifier: String, title: String, url: String, branch: String?, description: String?,
                     links: [String] = [], parent: String? = nil, blockedBy: [String] = []) -> String {
        var lines = ["Work on \(identifier): \(title)"]
        if let branch, !branch.isEmpty { lines.append("Branch: \(branch) (this folder is a worktree on it)") }
        lines.append("Issue: \(url)")
        if let parent { lines.append("Part of: \(parent)") }
        if !blockedBy.isEmpty { lines.append("Blocked by: \(blockedBy.joined(separator: ", "))") }
        let seen = Set([url])
        let extra = links.filter { !seen.contains($0) }
        if !extra.isEmpty { lines.append("Links: \(extra.joined(separator: " "))") }
        let head = lines.joined(separator: "\n")
        let body = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return head }
        let room = limit - head.count - 40
        let cut = body.count > room ? String(body.prefix(max(0, room))) + "\n[cut: read the rest in the issue]" : body
        return head + "\n\n" + cut
    }

    static func text(issue: LinearIssue, detail: LinearIssueDetail?) -> String {
        text(identifier: issue.identifier, title: issue.title, url: issue.url,
             branch: detail?.branchName ?? issue.branchName, description: detail?.description,
             links: (detail?.attachments?.nodes ?? []).map(\.url),
             parent: detail?.parent.map { "\($0.identifier) \($0.title)" },
             blockedBy: (detail?.blockedBy ?? []).map(\.identifier))
    }
}

/// How a tool is opened on a folder with the brief in its composer.
enum AgentLink {
    /// What opens the tool: a link the tool's app registered, or a script for a terminal.
    enum Opening: Equatable {
        case url(URL)
        /// A shell line run in a new terminal window, from `folder`; the brief is read from a file.
        case terminal(command: String)
    }

    /// Everything but unreserved characters is escaped, `+` and `&` included: the apps read the
    /// query with a parser that takes `+` for a space.
    static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
    }

    /// - Claude desktop app: `claude://code/new?q=&folder=`, the link its own Finder service uses
    ///   (read from the app, not documented: see docs/agents-integration.md, section 2.5).
    /// - Claude Code in a terminal: `claude-cli://open?cwd=&q=` (documented).
    /// - Codex app: `codex://new?prompt=&path=` (documented).
    /// - Codex in a terminal: `codex "<brief>"` (the CLI has no link).
    static func opening(tool: AgentTool, surface: AgentSurface, folder: URL, brief: String) -> Opening? {
        let path = escape(folder.path), prompt = escape(brief)
        switch (tool, surface) {
        case (.claudeCode, .app): return URL(string: "claude://code/new?q=\(prompt)&folder=\(path)").map(Opening.url)
        case (.claudeCode, .terminal): return URL(string: "claude-cli://open?cwd=\(path)&q=\(prompt)").map(Opening.url)
        case (.codex, .app): return URL(string: "codex://new?prompt=\(prompt)&path=\(path)").map(Opening.url)
        case (.codex, .terminal): return .terminal(command: "codex \"$(cat \"$DEVER_BRIEF\")\"")
        }
    }
}
