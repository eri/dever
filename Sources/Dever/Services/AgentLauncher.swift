import AppKit
import Foundation

/// Why an agent could not be started, in words the Delivery notice shows.
enum AgentLaunchError: LocalizedError, Equatable {
    case noFolder
    case noRepository
    case cloneNotFound(String)
    case noBranch
    case git(String)
    case cannotOpen(AgentTool, AgentSurface)

    var errorDescription: String? {
        switch self {
        case .noFolder: "Choose your code folder in Settings › Agents first"
        case .noRepository: "This project has no repository to open"
        case .cloneNotFound(let repository): "No clone of \(repository) under your code folder"
        case .noBranch: "Linear gives no branch name for this issue"
        case .git(let message): "git: \(message)"
        case .cannotOpen(let tool, let surface):
            surface == .app ? "\(tool.label)'s app did not open. Is it installed?" : "\(tool.label) did not open in a terminal"
        }
    }
}

/// Starts a coding agent on an issue: finds the clone, puts a worktree on the issue's branch,
/// and opens the tool there with the brief filled in. Nothing is sent for the user, and nothing
/// is read from or written to the tools' own files.
enum AgentLauncher {
    /// The folder the agent was opened in.
    @discardableResult
    static func start(tool: AgentTool, issue: LinearIssue, detail: LinearIssueDetail?, repository: String?) async throws -> URL {
        guard let root = AgentPreferences.root else { throw AgentLaunchError.noFolder }
        guard let repository else { throw AgentLaunchError.noRepository }
        guard let branch = (detail?.branchName ?? issue.branchName).flatMap({ $0.isEmpty ? nil : $0 }) else { throw AgentLaunchError.noBranch }
        let surface = AgentPreferences.surface(tool)
        let brief = AgentBrief.text(issue: issue, detail: detail)

        let folder = try await Task.detached(priority: .userInitiated) {
            guard let clone = CloneFinder.clone(of: repository, under: root) else { throw AgentLaunchError.cloneNotFound(repository) }
            return try worktree(clone: clone, root: root, repository: repository, branch: branch)
        }.value

        guard let opening = AgentLink.opening(tool: tool, surface: surface, folder: folder, brief: brief),
              await open(opening, folder: folder, brief: brief, name: issue.identifier) else {
            throw AgentLaunchError.cannotOpen(tool, surface)
        }
        AgentPreferences.lastTool = tool
        return folder
    }

    // MARK: Worktree

    /// The folder where `branch` is checked out: wherever it already is (the clone itself, a
    /// worktree another tool made), else a new worktree under the code folder.
    static func worktree(clone: URL, root: URL, repository: String, branch: String) throws -> URL {
        _ = git(["worktree", "prune"], in: clone)
        let list = git(["worktree", "list", "--porcelain"], in: clone)
        if list.status == 0, let path = AgentWorktree.checkedOut(branch: branch, inPorcelain: list.output),
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        // Best effort: a new branch should start from today's default branch, but a launch must not
        // wait on the network or fail without it.
        _ = git(["fetch", "--quiet", "origin"], in: clone, timeout: 20)
        let local = git(["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"], in: clone).status == 0
        let remote = git(["show-ref", "--verify", "--quiet", "refs/remotes/origin/\(branch)"], in: clone).status == 0
        let head = git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: clone)
        let base = head.status == 0 && !head.output.isEmpty ? head.output : "HEAD"
        let folder = AgentWorktree.folder(root: root, repository: repository, branch: branch)
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        let added = git(AgentWorktree.addArguments(folder: folder, branch: branch, existsLocally: local, existsOnOrigin: remote, base: base),
                        in: clone, timeout: 120)
        guard added.status == 0 else {
            let message = added.error.split(whereSeparator: \.isNewline).last.map(String.init) ?? "could not create the worktree"
            throw AgentLaunchError.git(message)
        }
        return folder
    }

    private static func git(_ arguments: [String], in folder: URL, timeout: TimeInterval = 15) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = folder
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "", error.localizedDescription) }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        deadline.cancel()
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines),
                error.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Opening

    @MainActor
    private static func open(_ opening: AgentLink.Opening, folder: URL, brief: String, name: String) -> Bool {
        switch opening {
        case .url(let url):
            // Only when an app answers the scheme: otherwise macOS shows its own "no application" alert.
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { return false }
            return NSWorkspace.shared.open(url)
        case .terminal(let command):
            // A terminal has no link: a small script, opened by the user's terminal app, reads the brief from a file.
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("dever-agent", isDirectory: true)
            let briefFile = scratch.appendingPathComponent("\(AgentWorktree.folderName(name)).brief.txt")
            let script = scratch.appendingPathComponent("\(AgentWorktree.folderName(name)).command")
            let text = """
            #!/bin/zsh -l
            cd \(quoted(folder.path)) || exit 1
            export DEVER_BRIEF=\(quoted(briefFile.path))
            \(command)

            """
            do {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try brief.write(to: briefFile, atomically: true, encoding: .utf8)
                try text.write(to: script, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            } catch { return false }
            return NSWorkspace.shared.open(script)
        }
    }

    /// A path as one shell word.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
