import XCTest
@testable import Dever

final class AgentSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_794_571_200)

    private func event(_ name: String, _ extra: String = "") -> AgentEvent {
        let json = "{\"hook_event_name\": \"\(name)\", \"session_id\": \"s1\", \"cwd\": \"/code/app\", \"prompt\": \"private words\"\(extra)}"
        return try! JSONDecoder().decode(AgentEvent.self, from: Data(json.utf8))
    }

    func testASessionGoesFromOpenToWorkingToWaitingToFinished() {
        var session = AgentSession.starting(event("SessionStart"), tool: .codex, at: start)
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(session.cwd, "/code/app")
        session = session.applying(event("UserPromptSubmit"), at: start.addingTimeInterval(60))
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.words(at: start.addingTimeInterval(5 * 60)), "Working · 4 min")
        session = session.applying(event("PermissionRequest", ", \"tool_name\": \"Bash\""), at: start.addingTimeInterval(120))
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.sentence, "Asks to use Bash")
        XCTAssertEqual(session.words(at: start.addingTimeInterval(5 * 60)), "Waiting for you · 3 min")
        // The permission was given: a tool ran.
        session = session.applying(event("PostToolUse", ", \"tool_name\": \"Bash\""), at: start.addingTimeInterval(180))
        XCTAssertEqual(session.state, .working)
        XCTAssertNil(session.sentence)
        session = session.applying(event("Stop", ", \"last_assistant_message\": \"First part.\\n\\nDone. Not verified:\\nlarge files.\""), at: start.addingTimeInterval(600))
        XCTAssertEqual(session.state, .finished)
        XCTAssertEqual(session.sentence, "Done. Not verified: large files.")
        XCTAssertEqual(session.words(at: start.addingTimeInterval(600 + 4 * 60)), "Finished 4 min ago")
        // A late tool event or an idle reminder does not reopen a finished turn.
        XCTAssertEqual(session.applying(event("PostToolUse"), at: start.addingTimeInterval(601)).state, .finished)
        XCTAssertEqual(session.applying(event("Notification", ", \"notification_type\": \"idle_prompt\", \"message\": \"Waiting\""),
                                        at: start.addingTimeInterval(700)).state, .finished)
        XCTAssertEqual(session.applying(event("SessionEnd"), at: start.addingTimeInterval(800)).state, .ended)
    }

    func testANoticeThatMeansYourTurnWaits() {
        let working = AgentSession.starting(event("UserPromptSubmit"), tool: .claudeCode, at: start)
        XCTAssertEqual(working.state, .working)
        let asked = working.applying(event("Notification", ", \"notification_type\": \"permission_prompt\", \"message\": \"Claude needs your permission\""), at: start)
        XCTAssertEqual(asked.state, .waiting)
        XCTAssertEqual(asked.sentence, "Claude needs your permission")
        XCTAssertEqual(working.applying(event("Notification", ", \"notification_type\": \"auth_success\""), at: start).state, .working)
    }

    func testAWorkingSessionThatWentQuietSaysSo() {
        let session = AgentSession.starting(event("UserPromptSubmit"), tool: .claudeCode, at: start)
        XCTAssertFalse(session.stale(at: start.addingTimeInterval(9 * 60)))
        let later = start.addingTimeInterval(14 * 60)
        XCTAssertTrue(session.stale(at: later))
        XCTAssertEqual(session.words(at: later), "Working · last heard 14 min ago")
        // Waiting does not go stale: it waits for the user.
        let waiting = session.applying(event("PermissionRequest"), at: start)
        XCTAssertFalse(waiting.stale(at: later))
    }

    func testNothingPrivateIsKept() {
        let kept = event("UserPromptSubmit")
        XCTAssertFalse(String(describing: kept).contains("private words"))
        XCTAssertThrowsError(try JSONDecoder().decode(AgentEvent.self, from: Data("{\"hook_event_name\": \"Stop\"}".utf8)))
    }

    func testTheSessionShownForAnIssueIsTheOneOnItsBranchThatNeedsYouFirst() {
        func session(_ id: String, _ state: AgentSession.State, branch: String?, heard: TimeInterval) -> AgentSession {
            AgentSession(id: id, tool: .codex, cwd: nil, branch: branch, state: state, sentence: nil, since: start, heard: start.addingTimeInterval(heard))
        }
        let all = [session("a", .working, branch: "sam/eng-1", heard: 50), session("b", .waiting, branch: "Sam/ENG-1", heard: 10),
                   session("c", .ended, branch: "sam/eng-1", heard: 90), session("d", .working, branch: "sam/eng-2", heard: 99),
                   session("e", .working, branch: nil, heard: 99)]
        XCTAssertEqual(AgentSession.current(for: "sam/eng-1", in: all)?.id, "b")
        XCTAssertEqual(AgentSession.current(for: "sam/eng-2", in: all)?.id, "d")
        XCTAssertNil(AgentSession.current(for: "sam/eng-3", in: all))
        XCTAssertNil(AgentSession.current(for: nil, in: all))
        XCTAssertNil(AgentSession.current(for: "", in: all))
        XCTAssertEqual(session("x", .working, branch: nil, heard: 0).link?.absoluteString, "codex://threads/x")
    }

    func testTheBridgeReadsOneRequest() {
        let body = "{\"a\": 1}"
        let head = "POST /hook/codex HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer abc\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        XCTAssertEqual(BridgeRequest.parse(Data((head + body).utf8)),
                       .request(method: "POST", path: "/hook/codex", bearer: "abc", body: Data(body.utf8)))
        XCTAssertEqual(BridgeRequest.parse(Data((head + "{\"a\"").utf8)), .incomplete)
        XCTAssertEqual(BridgeRequest.parse(Data("POST /hook/codex HTTP/1.1\r\nHost".utf8)), .incomplete)
        XCTAssertEqual(BridgeRequest.parse(Data("nonsense\r\n\r\n".utf8)), .malformed)
        XCTAssertEqual(BridgeRequest.parse(Data("GET / HTTP/1.1\r\n\r\n".utf8)), .request(method: "GET", path: "/", bearer: nil, body: Data()))
    }

    func testThePluginRunsOneCommandPerEventAndNamesTheTool() throws {
        for tool in AgentTool.allCases {
            let files = AgentPlugin.files(tool, hook: "/Users/someone/Library/Application Support/Dever/agent/dever-hook")
            XCTAssertEqual(files.count, 3)
            for (path, text) in files {
                XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(text.utf8)), path)
            }
            let hooksPath = try XCTUnwrap(files.keys.first { $0.hasSuffix("hooks/hooks.json") })
            let hooks = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(files[hooksPath]!.utf8)) as? [String: [String: Any]])["hooks"]!
            XCTAssertEqual(Set(hooks.keys), Set(AgentPlugin.events(tool)))
            let first = try XCTUnwrap(((hooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: String]])?.first)
            XCTAssertEqual(first["type"], "command")
            XCTAssertEqual(first["command"], "'/Users/someone/Library/Application Support/Dever/agent/dever-hook' \(tool.rawValue)")
            XCTAssertTrue(AgentPlugin.events(tool).contains("SessionStart"))
        }
        XCTAssertEqual(AgentPlugin.arguments(.codex, ["list"]), ["-c", "approval_policy=\"on-request\"", "plugin", "list"])
        XCTAssertEqual(AgentPlugin.arguments(.claudeCode, ["list"]), ["plugin", "list"])
        XCTAssertTrue(AgentPlugin.hookScript.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(AgentPlugin.hookScript.contains("exit 0"))
    }

    /// The whole path, for real: the hook command posts a payload to the listener, and the session
    /// appears in the store. In a folder of its own, away from a Dever that may be running.
    @MainActor
    func testAHookCallReachesTheStoreThroughTheBridge() async throws {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("dever-bridge-\(UUID().uuidString)")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        setenv("DEVER_AGENT_FOLDER", folder.path, 1)
        defer { unsetenv("DEVER_AGENT_FOLDER") }
        AgentBridge.shared.start()
        let address = folder.appendingPathComponent("bridge.json")
        for _ in 0..<50 where !files.fileExists(atPath: address.path) { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertTrue(files.fileExists(atPath: address.path))
        XCTAssertEqual(try files.attributesOfItem(atPath: address.path)[.posixPermissions] as? Int, 0o600)

        let script = folder.appendingPathComponent("dever-hook")
        try AgentPlugin.hookScript.write(to: script, atomically: true, encoding: .utf8)
        func call(_ payload: String, bridge: String) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, "codex"]
            process.environment = ["DEVER_BRIDGE": bridge, "HOME": folder.path]
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(payload.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            return process.terminationStatus
        }
        let id = "bridge-test-\(UUID().uuidString)"
        XCTAssertEqual(try call("{\"hook_event_name\": \"UserPromptSubmit\", \"session_id\": \"\(id)\", \"prompt\": \"secret\"}", bridge: address.path), 0)
        for _ in 0..<50 where AgentStore.shared.sessions[id] == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(AgentStore.shared.sessions[id]?.state, .working)
        XCTAssertEqual(AgentStore.shared.sessions[id]?.tool, .codex)

        // Without Dever (no address file), and with a wrong token, the hook still succeeds and nothing arrives.
        XCTAssertEqual(try call("{}", bridge: folder.appendingPathComponent("absent.json").path), 0)
        let forged = folder.appendingPathComponent("forged.json")
        let real = try String(contentsOf: address, encoding: .utf8)
        let port = try XCTUnwrap(real.split(separator: ",").first?.split(separator: ":").last?.trimmingCharacters(in: .whitespaces))
        try "{\"port\": \(port), \"token\": \"00\"}".write(to: forged, atomically: true, encoding: .utf8)
        let other = "forged-\(UUID().uuidString)"
        XCTAssertEqual(try call("{\"hook_event_name\": \"Stop\", \"session_id\": \"\(other)\"}", bridge: forged.path), 0)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(AgentStore.shared.sessions[other])
    }

    /// Against the tools installed on this Mac, each with a configuration folder made for the test
    /// (theirs is never touched): `DEVER_TEST_REAL_TOOLS=1 swift test --filter RealTools`.
    @MainActor
    func testRealToolsInstallAndRemoveThePlugin() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEVER_TEST_REAL_TOOLS"] == "1", "needs the tools: DEVER_TEST_REAL_TOOLS=1")
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("dever-tools-\(UUID().uuidString)")
        try files.createDirectory(at: folder.appendingPathComponent("claude-home"), withIntermediateDirectories: true)
        try files.createDirectory(at: folder.appendingPathComponent("codex-home"), withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        setenv("DEVER_AGENT_FOLDER", folder.appendingPathComponent("agent").path, 1)
        setenv("CLAUDE_CONFIG_DIR", folder.appendingPathComponent("claude-home").path, 1)
        setenv("CODEX_HOME", folder.appendingPathComponent("codex-home").path, 1)
        defer { unsetenv("DEVER_AGENT_FOLDER"); unsetenv("CLAUDE_CONFIG_DIR"); unsetenv("CODEX_HOME") }
        var tried = 0
        for tool in AgentTool.allCases {
            guard let binary = AgentPlugin.binary(tool, codexApp: AgentApps.app(.codex)) else { continue }
            tried += 1
            let before = await AgentPlugin.connected(tool, binary: binary)
            XCTAssertFalse(before, tool.label)
            try await AgentPlugin.connect(tool, binary: binary)
            let after = await AgentPlugin.connected(tool, binary: binary)
            XCTAssertTrue(after, tool.label)
            // Connecting twice replaces, it does not fail.
            try await AgentPlugin.connect(tool, binary: binary)
            try await AgentPlugin.disconnect(tool, binary: binary)
            let gone = await AgentPlugin.connected(tool, binary: binary)
            XCTAssertFalse(gone, tool.label)
        }
        XCTAssertGreaterThan(tried, 0, "no tool found on this Mac")
    }
}
