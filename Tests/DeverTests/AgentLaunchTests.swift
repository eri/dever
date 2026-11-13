import XCTest
@testable import Dever

final class AgentLaunchTests: XCTestCase {
    func testSlugFromRemotes() {
        XCTAssertEqual(CloneFinder.slug(fromRemote: "git@github.com:Acme/App.git"), "acme/app")
        XCTAssertEqual(CloneFinder.slug(fromRemote: "https://github.com/acme/app"), "acme/app")
        XCTAssertEqual(CloneFinder.slug(fromRemote: "https://github.com/acme/app.git/"), "acme/app")
        XCTAssertEqual(CloneFinder.slug(fromRemote: "ssh://git@github.com/acme/app.git"), "acme/app")
        XCTAssertNil(CloneFinder.slug(fromRemote: "/srv/git/app.git"))
        XCTAssertNil(CloneFinder.slug(fromRemote: "https://example.com/group/sub/app.git"))
    }

    func testOriginURLIsReadFromItsOwnSection() {
        let config = """
        [core]
        \tbare = false
        [remote "upstream"]
        \turl = git@github.com:other/app.git
        [remote "origin"]
        \turl = git@github.com:acme/app.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        [branch "main"]
        \tremote = origin
        """
        XCTAssertEqual(CloneFinder.originURL(inConfig: config), "git@github.com:acme/app.git")
        XCTAssertNil(CloneFinder.originURL(inConfig: "[core]\n\tbare = false"))
    }

    func testClonesAreFoundByRemoteAndWorktreesAreNot() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("dever-clones-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        func clone(_ path: String, remote: String) throws {
            let git = root.appendingPathComponent(path).appendingPathComponent(".git")
            try files.createDirectory(at: git, withIntermediateDirectories: true)
            try "[remote \"origin\"]\n\turl = \(remote)\n".write(to: git.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        }
        try clone("work/app", remote: "git@github.com:acme/app.git")
        try clone("work/app/packages/inner", remote: "git@github.com:acme/inner.git")   // inside a clone: not searched
        try clone("api", remote: "https://github.com/Acme/API.git")
        try clone("node_modules/dep", remote: "git@github.com:acme/dep.git")
        try clone(".dever/worktrees/app/hidden", remote: "git@github.com:acme/hidden.git")
        try clone("a/b/c/d/deep", remote: "git@github.com:acme/deep.git")
        // A worktree: `.git` is a file.
        let worktree = root.appendingPathComponent("work/app-feature")
        try files.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: /elsewhere".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let found = CloneFinder.clones(under: root)
        XCTAssertEqual(Set(found.keys), ["acme/app", "acme/api"])
        XCTAssertEqual(found["acme/app"]?.lastPathComponent, "app")
        XCTAssertEqual(CloneFinder.clone(of: "Acme/Api", under: root)?.lastPathComponent, "api")
        XCTAssertNil(CloneFinder.clone(of: "acme/deep", under: root))
    }

    func testWorktreeFolderAndArguments() {
        let root = URL(fileURLWithPath: "/code", isDirectory: true)
        let folder = AgentWorktree.folder(root: root, repository: "acme/app", branch: "sam/eng-12-export csv")
        XCTAssertEqual(folder.path, "/code/.dever/worktrees/app/sam-eng-12-export-csv")
        XCTAssertEqual(AgentWorktree.addArguments(folder: folder, branch: "b", existsLocally: true, existsOnOrigin: true, base: "origin/main"),
                       ["worktree", "add", folder.path, "b"])
        XCTAssertEqual(AgentWorktree.addArguments(folder: folder, branch: "b", existsLocally: false, existsOnOrigin: true, base: "origin/main"),
                       ["worktree", "add", "--track", "-b", "b", folder.path, "origin/b"])
        XCTAssertEqual(AgentWorktree.addArguments(folder: folder, branch: "b", existsLocally: false, existsOnOrigin: false, base: "origin/main"),
                       ["worktree", "add", "-b", "b", folder.path, "origin/main"])
    }

    func testBranchAlreadyCheckedOutIsFound() {
        let list = """
        worktree /code/app
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /code/.dever/worktrees/app/sam-eng-12
        HEAD 2222222222222222222222222222222222222222
        branch refs/heads/sam/eng-12

        worktree /elsewhere/detached
        HEAD 3333333333333333333333333333333333333333
        detached
        """
        XCTAssertEqual(AgentWorktree.checkedOut(branch: "sam/eng-12", inPorcelain: list), "/code/.dever/worktrees/app/sam-eng-12")
        XCTAssertEqual(AgentWorktree.checkedOut(branch: "main", inPorcelain: list), "/code/app")
        XCTAssertNil(AgentWorktree.checkedOut(branch: "sam/eng-1", inPorcelain: list))
    }

    func testBriefIsShortAndCutUnderTheLimit() {
        let brief = AgentBrief.text(identifier: "ENG-12", title: "Export CSV", url: "https://linear.app/x/issue/ENG-12",
                                    branch: "sam/eng-12-export", description: "  Export respects the filters.\n",
                                    links: ["https://linear.app/x/issue/ENG-12", "https://example.com/thread"],
                                    parent: "ENG-1 Reports", blockedBy: ["ENG-9"])
        XCTAssertEqual(brief, """
        Work on ENG-12: Export CSV
        Branch: sam/eng-12-export (this folder is a worktree on it)
        Issue: https://linear.app/x/issue/ENG-12
        Part of: ENG-1 Reports
        Blocked by: ENG-9
        Links: https://example.com/thread

        Export respects the filters.
        """)
        let long = AgentBrief.text(identifier: "ENG-12", title: "T", url: "u", branch: nil,
                                   description: String(repeating: "a", count: 40_000))
        XCTAssertLessThanOrEqual(long.count, AgentBrief.limit)
        XCTAssertTrue(long.hasSuffix("[cut: read the rest in the issue]"))
        XCTAssertEqual(AgentBrief.text(identifier: "ENG-1", title: "T", url: "u", branch: nil, description: nil), "Work on ENG-1: T\nIssue: u")
    }

    func testLinksEscapeEverythingAParserCouldMisread() {
        let folder = URL(fileURLWithPath: "/code/my app", isDirectory: true)
        let brief = "a+b & c=d\nnext"
        XCTAssertEqual(AgentLink.opening(tool: .claudeCode, surface: .app, folder: folder, brief: brief),
                       .url(URL(string: "claude://code/new?q=a%2Bb%20%26%20c%3Dd%0Anext&folder=%2Fcode%2Fmy%20app")!))
        XCTAssertEqual(AgentLink.opening(tool: .claudeCode, surface: .terminal, folder: folder, brief: "x"),
                       .url(URL(string: "claude-cli://open?cwd=%2Fcode%2Fmy%20app&q=x")!))
        XCTAssertEqual(AgentLink.opening(tool: .codex, surface: .app, folder: folder, brief: "x"),
                       .url(URL(string: "codex://new?prompt=x&path=%2Fcode%2Fmy%20app")!))
        XCTAssertEqual(AgentLink.opening(tool: .codex, surface: .terminal, folder: folder, brief: "x"),
                       .terminal(command: "codex \"$(cat \"$DEVER_BRIEF\")\""))
        XCTAssertEqual(AgentLauncher.quoted("/a/it's"), "'/a/it'\\''s'")
    }

    /// Against a real repository made for the test: the worktree is created on the issue's branch,
    /// and a second start finds the branch where it already is.
    func testWorktreeIsCreatedOnceOnTheBranch() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("dever-worktree-\(UUID().uuidString)").resolvingSymlinksInPath()
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

        let folder = try AgentLauncher.worktree(clone: clone, root: root, repository: "acme/app", branch: "sam/eng-12-export")
        XCTAssertEqual(folder.path, root.appendingPathComponent(".dever/worktrees/app/sam-eng-12-export").path)
        XCTAssertTrue(files.fileExists(atPath: folder.appendingPathComponent("README").path))
        let again = try AgentLauncher.worktree(clone: clone, root: root, repository: "acme/app", branch: "sam/eng-12-export")
        XCTAssertEqual(again.resolvingSymlinksInPath().path, folder.path)
        // The branch the clone itself is on opens the clone.
        XCTAssertEqual(try AgentLauncher.worktree(clone: clone, root: root, repository: "acme/app", branch: "main").resolvingSymlinksInPath().path, clone.path)
    }
}
