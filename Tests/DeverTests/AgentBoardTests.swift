import XCTest
@testable import Dever

final class AgentBoardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_571_200)

    private func session(_ id: String, _ state: AgentSession.State, branch: String?, heard: TimeInterval = 0, cwd: String? = nil) -> AgentSession {
        AgentSession(id: id, tool: .codex, cwd: cwd, branch: branch, state: state, sentence: nil, since: now, heard: now.addingTimeInterval(heard))
    }

    private func issue(_ n: Int, branch: String) -> LinearIssue {
        LinearIssue(id: "i\(n)", identifier: "ENG-\(n)", title: "T\(n)", url: "", updatedAt: "",
                    state: .init(id: nil, name: "In Progress", type: "started", color: nil), assignee: nil, branchName: branch,
                    attachments: nil, priority: nil, dueDate: nil, labels: nil, archivedAt: nil)
    }

    func testSessionsAreGroupedByProjectWithWhatWaitsFirst() {
        let web = Project(name: "Web"), api = Project(name: "API"), quiet = Project(name: "Quiet")
        let issues: [UUID: [LinearIssue]] = [web.id: [issue(1, branch: "sam/eng-1"), issue(2, branch: "sam/eng-2")],
                                             api.id: [issue(3, branch: "sam/eng-3")]]
        let sessions = [session("a", .working, branch: "sam/eng-1", heard: 50), session("b", .waiting, branch: "Sam/ENG-2"),
                        session("c", .finished, branch: "sam/eng-3"), session("d", .working, branch: "spike"),
                        session("e", .ended, branch: "sam/eng-1"), session("f", .ready, branch: nil), session("g", .finished, branch: "sam/eng-1", heard: 10)]
        let groups = AgentBoard.groups(sessions: sessions, projects: [web, api, quiet]) { issues[$0.id] ?? [] }
        XCTAssertEqual(groups.map { $0.project?.name ?? "other" }, ["Web", "API", "other"])
        // Waiting, then finished, then working; a closed session is not listed.
        XCTAssertEqual(groups[0].rows.map(\.session.id), ["b", "g", "a"])
        XCTAssertEqual(groups[0].rows.map { $0.issue?.identifier }, ["ENG-2", "ENG-1", "ENG-1"])
        XCTAssertEqual(groups[1].rows.map(\.session.id), ["c"])
        XCTAssertEqual(groups[2].rows.map(\.session.id), ["d", "f"])
        XCTAssertNil(groups[2].rows[0].issue)
        XCTAssertEqual(AgentBoard.waiting(sessions), 1)
        XCTAssertTrue(AgentBoard.groups(sessions: [session("e", .ended, branch: "x")], projects: [web]) { _ in [] }.isEmpty)
    }

    func testAWorktreeGoesOnlyWhenMergedCleanAndFree() {
        let entry = AgentWorktreeEntry(path: URL(fileURLWithPath: "/code/.dever/worktrees/app/sam-eng-1"), clone: URL(fileURLWithPath: "/code/app"),
                                       repository: "acme/app", branch: "sam/eng-1", dirty: false)
        XCTAssertEqual(entry.standing(sessions: [], mergedBranches: ["sam/eng-1"]), .removable)
        XCTAssertEqual(entry.standing(sessions: [], mergedBranches: []), .notMerged)
        var dirty = entry
        dirty.dirty = true
        XCTAssertEqual(dirty.standing(sessions: [], mergedBranches: ["sam/eng-1"]), .uncommitted)
        // A session open in it keeps it, whatever else is true; a closed one does not.
        let inside = session("s", .working, branch: "sam/eng-1", cwd: "/code/.dever/worktrees/app/sam-eng-1")
        XCTAssertEqual(entry.standing(sessions: [inside], mergedBranches: ["sam/eng-1"]), .inUse(.codex))
        XCTAssertEqual(entry.standing(sessions: [session("s", .ended, branch: nil, cwd: "/code/.dever/worktrees/app/sam-eng-1")],
                                      mergedBranches: ["sam/eng-1"]), .removable)
        var detached = entry
        detached.branch = nil
        XCTAssertEqual(detached.standing(sessions: [], mergedBranches: ["sam/eng-1"]), .notMerged)
    }

    /// Against a repository made for the test: Dever's worktrees are found beside the clone, a clean
    /// one is removed, and git itself refuses one that holds uncommitted work.
    func testWorktreesAreFoundAndOnlyACleanOneIsRemoved() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("dever-board-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? files.removeItem(at: root) }
        let clone = root.appendingPathComponent("app")
        try files.createDirectory(at: clone, withIntermediateDirectories: true)
        func git(_ arguments: String...) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"] + arguments
            process.currentDirectoryURL = clone
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
        }
        try git("init", "--quiet", "-b", "main")
        try "hello".write(to: clone.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        try git("add", "README")
        try git("commit", "--quiet", "-m", "first")
        let clean = try AgentLauncher.worktree(clone: clone, branch: "sam/eng-1")
        let busy = try AgentLauncher.worktree(clone: clone, branch: "sam/eng-2")
        try "work".write(to: busy.appendingPathComponent("NOTES"), atomically: true, encoding: .utf8)

        XCTAssertEqual(AgentWorktrees.folders(clone: clone).map(\.lastPathComponent), ["sam-eng-1", "sam-eng-2"])
        let found = AgentWorktrees.scan(clones: ["acme/app": clone.path])
        XCTAssertEqual(found.map(\.branch), ["sam/eng-1", "sam/eng-2"])
        XCTAssertEqual(found.map(\.dirty), [false, true])
        XCTAssertEqual(found.map(\.repository), ["acme/app", "acme/app"])

        XCTAssertThrowsError(try AgentWorktrees.remove(found[1]))
        XCTAssertTrue(files.fileExists(atPath: busy.appendingPathComponent("NOTES").path))
        try AgentWorktrees.remove(found[0])
        XCTAssertFalse(files.fileExists(atPath: clean.path))
        XCTAssertEqual(AgentWorktrees.scan(clones: ["acme/app": clone.path]).map(\.branch), ["sam/eng-2"])
        // A clone with no worktree of Dever's, or one that is gone, lists nothing.
        XCTAssertTrue(AgentWorktrees.scan(clones: ["acme/none": root.appendingPathComponent("none").path]).isEmpty)
    }
}
