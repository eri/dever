import Foundation

// The agents' board (docs/agents-integration.md, phase 5): every session Dever hears, across
// projects, tied to its issue where its branch names one; and the worktrees Dever made, with
// whether each can go. The board lists and links; it starts and steers nothing.

enum AgentBoard {
    struct Row: Identifiable, Equatable {
        var session: AgentSession
        var issue: LinearIssue?
        var id: String { session.id }

        static func == (a: Row, b: Row) -> Bool { a.session == b.session && a.issue?.id == b.issue?.id }
    }

    /// A project's sessions; `project` is nil for those on no known issue's branch.
    struct Group: Identifiable {
        var project: Project?
        var rows: [Row]
        var id: String { project?.id.uuidString ?? "other" }
    }

    /// What needs the developer comes first: waiting, then finished, working, open.
    static func order(_ state: AgentSession.State) -> Int {
        switch state {
        case .waiting: 0
        case .finished: 1
        case .working: 2
        case .ready: 3
        case .ended: 4
        }
    }

    /// The sessions still open, grouped by project in the projects' order, the ones on no issue last.
    static func groups(sessions: [AgentSession], projects: [Project], issues: (Project) -> [LinearIssue]) -> [Group] {
        let open = sessions.filter { $0.state != .ended }
            .sorted { (order($0.state), -$0.heard.timeIntervalSince1970, $0.id) < (order($1.state), -$1.heard.timeIntervalSince1970, $1.id) }
        var left = open
        var groups: [Group] = []
        for project in projects {
            var byBranch: [String: LinearIssue] = [:]
            for issue in issues(project) {
                if let branch = issue.branchName?.lowercased(), !branch.isEmpty, byBranch[branch] == nil { byBranch[branch] = issue }
            }
            let mine = left.compactMap { session -> Row? in
                guard let branch = session.branch?.lowercased(), let issue = byBranch[branch] else { return nil }
                return Row(session: session, issue: issue)
            }
            guard !mine.isEmpty else { continue }
            left.removeAll { session in mine.contains { $0.session.id == session.id } }
            groups.append(Group(project: project, rows: mine))
        }
        if !left.isEmpty { groups.append(Group(project: nil, rows: left.map { Row(session: $0, issue: nil) })) }
        return groups
    }

    /// How many sessions wait for the developer: the rail's dot.
    static func waiting(_ sessions: [AgentSession]) -> Int { sessions.filter { $0.state == .waiting }.count }
}

/// A worktree Dever made for an agent, and whether it can go.
struct AgentWorktreeEntry: Identifiable, Equatable {
    var path: URL
    var clone: URL
    var repository: String
    var branch: String?
    /// Uncommitted or untracked work in it.
    var dirty: Bool
    var id: String { path.path }

    enum Standing: Equatable {
        /// A session is open in it.
        case inUse(AgentTool)
        case uncommitted
        case notMerged
        /// Its pull request is merged and nothing is left in it: it can be removed.
        case removable
    }

    func standing(sessions: [AgentSession], mergedBranches: Set<String>) -> Standing {
        if let session = sessions.first(where: { $0.state != .ended && $0.cwd.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == path.standardizedFileURL.path }) {
            return .inUse(session.tool)
        }
        if dirty { return .uncommitted }
        guard let branch, mergedBranches.contains(branch.lowercased()) else { return .notMerged }
        return .removable
    }
}

enum AgentWorktrees {
    /// The folders under `<the clone's parent>/.dever/worktrees/<clone>`: the ones Dever made.
    static func folders(clone: URL, files: FileManager = .default) -> [URL] {
        let root = AgentWorktree.folder(clone: clone, branch: "x").deletingLastPathComponent()
        let children = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.path < $1.path }
    }

    /// Every worktree Dever made beside the clones it knows, read with git.
    static func scan(clones: [String: String]) -> [AgentWorktreeEntry] {
        var out: [AgentWorktreeEntry] = []
        for (repository, path) in clones.sorted(by: { $0.key < $1.key }) {
            let clone = URL(fileURLWithPath: path, isDirectory: true)
            for folder in folders(clone: clone) {
                let branch = AgentLauncher.git(["rev-parse", "--abbrev-ref", "HEAD"], in: folder, timeout: 5)
                let status = AgentLauncher.git(["status", "--porcelain"], in: folder, timeout: 10)
                // A folder git cannot read is left alone: counted as having work in it.
                out.append(AgentWorktreeEntry(path: folder, clone: clone, repository: repository,
                                              branch: branch.status == 0 && branch.output != "HEAD" && !branch.output.isEmpty ? branch.output : nil,
                                              dirty: status.status != 0 || !status.output.isEmpty))
            }
        }
        return out
    }

    /// Removes a worktree with git, which itself refuses one that holds uncommitted work: nothing is forced.
    static func remove(_ entry: AgentWorktreeEntry) throws {
        let removed = AgentLauncher.git(["worktree", "remove", entry.path.path], in: entry.clone, timeout: 60)
        guard removed.status == 0 else {
            throw AgentLaunchError.git(removed.error.split(whereSeparator: \.isNewline).last.map(String.init) ?? "could not remove the worktree")
        }
    }
}
