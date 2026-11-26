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
            let files = AgentPlugin.files(tool, hook: "/Users/someone/Library/Application Support/Dever/agent/dever-hook",
                                          context: "/Users/someone/Library/Application Support/Dever/agent/dever-mcp")
            XCTAssertEqual(files.count, 5)
            for (path, text) in files where path.hasSuffix(".json") {
                XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(text.utf8)), path)
            }
            // The MCP server is one command with the tool's name, and the skill comes with it.
            let mcpPath = try XCTUnwrap(files.keys.first { $0.hasSuffix(".mcp.json") })
            let servers = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(files[mcpPath]!.utf8)) as? [String: [String: [String: Any]]])["mcpServers"]!
            XCTAssertEqual(servers["dever"]?["command"] as? String, "/Users/someone/Library/Application Support/Dever/agent/dever-mcp")
            XCTAssertEqual(servers["dever"]?["args"] as? [String], [tool.rawValue])
            XCTAssertTrue(files.keys.contains { $0.hasSuffix("skills/dever/SKILL.md") })
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

        // A question from the agent takes the same road: the plugin's MCP command carries it and brings the answer back.
        let mcp = folder.appendingPathComponent("dever-mcp")
        try AgentPlugin.contextScript.write(to: mcp, atomically: true, encoding: .utf8)
        // Off the main actor: Dever answers on it, as in the app, where the agent is another process.
        func ask(_ lines: [String], bridge: String) async throws -> [[String: Any]] {
            let text = try await Task.detached { try exchange(lines, script: mcp.path, bridge: bridge, home: folder.path) }.value
            return text.split(whereSeparator: \.isNewline).compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        }
        @Sendable func exchange(_ lines: [String], script: String, bridge: String, home: String) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script, "codex"]
            process.environment = ["DEVER_BRIDGE": bridge, "HOME": home]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            input.fileHandleForWriting.write(Data((lines.joined(separator: "\n") + "\n").utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        let answers = try await ask([#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#,
                               #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
                               #"{"jsonrpc":"2.0","id":"two","method":"tools/list"}"#,
                               #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_issue","arguments":{}}}"#], bridge: address.path)
        XCTAssertEqual(answers.count, 3)
        XCTAssertEqual((answers[0]["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual(answers[1]["id"] as? String, "two")
        let listed = ((answers[1]["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(listed, ["get_issue", "get_thread", "get_pull_requests", "propose_update", "report_usage"])
        XCTAssertEqual((answers[2]["result"] as? [String: Any])?["isError"] as? Bool, true)
        // Without Dever the command answers for it, with the request's own id.
        let alone = try await ask([#"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#],
                            bridge: folder.appendingPathComponent("absent.json").path)
        XCTAssertEqual(alone.count, 1)
        XCTAssertEqual(alone.first?["id"] as? Int, 7)
        XCTAssertNotNil(alone.first?["error"])

        // A Stop on a branch no issue has: the hook prints nothing, and the agent stops as usual.
        let stopped = Process()
        stopped.executableURL = URL(fileURLWithPath: "/bin/sh")
        stopped.arguments = [script.path, "codex"]
        stopped.environment = ["DEVER_BRIDGE": address.path, "HOME": folder.path]
        let stopIn = Pipe(), stopOut = Pipe()
        stopped.standardInput = stopIn
        stopped.standardOutput = stopOut
        try stopped.run()
        stopIn.fileHandleForWriting.write(Data("{\"hook_event_name\": \"Stop\", \"session_id\": \"\(id)\", \"cwd\": \"\(folder.path)\"}".utf8))
        try stopIn.fileHandleForWriting.close()
        let printed = try await Task.detached { stopOut.fileHandleForReading.readDataToEndOfFile() }.value
        stopped.waitUntilExit()
        XCTAssertEqual(stopped.terminationStatus, 0)
        XCTAssertTrue(printed.isEmpty)

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
            if ProcessInfo.processInfo.environment["DEVER_TEST_PRINT"] == "1" {
                for arguments in tool == .claudeCode ? [["plugin", "details", "dever@dever"], ["mcp", "list"]] : [["mcp", "list"]] {
                    let process = Process()
                    process.executableURL = binary
                    process.arguments = (tool == .codex ? ["-c", "approval_policy=\"on-request\""] : []) + arguments
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    process.standardInput = FileHandle.nullDevice
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    print("=== \(tool.rawValue) \(arguments.joined(separator: " "))\n" + String(decoding: data, as: UTF8.self))
                }
            }
            // Connecting twice replaces, it does not fail.
            try await AgentPlugin.connect(tool, binary: binary)
            try await AgentPlugin.disconnect(tool, binary: binary)
            let gone = await AgentPlugin.connected(tool, binary: binary)
            XCTAssertFalse(gone, tool.label)
        }
        XCTAssertGreaterThan(tried, 0, "no tool found on this Mac")
    }

    func testAnAgentsQuestionIsReadAndAnsweredInTheProtocol() throws {
        func read(_ json: String) -> AgentMCP.Request? { AgentMCP.read(Data(json.utf8))?.request }
        XCTAssertEqual(read(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"x"}}"#), .initialize(version: "x"))
        XCTAssertEqual(read(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#), .list)
        XCTAssertEqual(read(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#), .notification)
        XCTAssertEqual(read(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_thread","arguments":{"issue":"ENG-12"}}}"#),
                       .call(.init(tool: "get_thread", arguments: ["issue": "ENG-12"])))
        XCTAssertEqual(read(#"{"jsonrpc":"2.0","id":2,"method":"resources/list"}"#), .unknown("resources/list"))
        XCTAssertNil(read("not json"))
        // A switched-off agent is offered nothing.
        XCTAssertEqual((AgentMCP.listing(allowed: false)["tools"] as? [Any])?.count, 0)
        let offered = try XCTUnwrap(AgentMCP.listing(allowed: true)["tools"] as? [[String: Any]])
        XCTAssertEqual(offered.count, 5)
        // Only the proposal is not read-only, and it asks for a summary.
        let propose = try XCTUnwrap(offered.first { $0["name"] as? String == "propose_update" })
        XCTAssertEqual((propose["annotations"] as? [String: Bool])?["readOnlyHint"], false)
        XCTAssertEqual((propose["inputSchema"] as? [String: Any])?["required"] as? [String], ["issue", "summary"])
        XCTAssertEqual((offered[0]["annotations"] as? [String: Bool])?["readOnlyHint"], true)
        let answer = try XCTUnwrap(JSONSerialization.jsonObject(with: AgentMCP.text("hello", id: 5)) as? [String: Any])
        XCTAssertEqual(answer["id"] as? Int, 5)
        XCTAssertEqual(((answer["result"] as? [String: Any])?["content"] as? [[String: String]])?.first?["text"], "hello")
    }

    func testWhatAnAgentIsToldOfAThreadAndOfPullRequests() throws {
        let now = Date(timeIntervalSince1970: 1_794_571_200)
        // A message's link, and a reply's link with its parent.
        let parent = try XCTUnwrap(AgentContextText.slackLocation("https://team.slack.com/archives/C0123/p1700000000123456"))
        XCTAssertEqual(parent.channel, "C0123")
        XCTAssertEqual(parent.ts, "1700000000.123456")
        XCTAssertNil(parent.thread)
        XCTAssertEqual(AgentContextText.slackLocation("https://team.slack.com/archives/C0123/p1700000999000100?thread_ts=1700000000.123456&cid=C0123")?.thread,
                       "1700000000.123456")
        XCTAssertNil(AgentContextText.slackLocation("https://github.com/acme/app/pull/3"))
        XCTAssertNil(AgentContextText.slackLocation("https://team.slack.com/archives/C0123"))

        XCTAssertEqual(AgentContextText.mentions("ask <@U1> and <@U9>", names: ["U1": "Ana"]), "ask @Ana and <@U9>")
        let messages = [SlackMessage(ts: "1700000100.000000", user: "U2", text: "On it <@U1>"),
                        SlackMessage(ts: "1700000000.000000", user: "U1", text: "Export is broken")]
        let thread = AgentContextText.thread(messages, names: ["U1": "Ana", "U2": "Sam"], channel: "app", now: now)
        XCTAssertTrue(thread.hasPrefix("Slack thread in #app (2 messages, oldest first):"))
        XCTAssertLessThan(try XCTUnwrap(thread.range(of: "Ana: Export is broken")).lowerBound, try XCTUnwrap(thread.range(of: "Sam: On it @Ana")).lowerBound)

        let open = GitHubPull(id: 1, number: 12, title: "Export CSV", html_url: "https://github.com/acme/app/pull/12", draft: false,
                              user: .init(login: "sam"), updated_at: "", head: .init(ref: "sam/eng-12"), merged_at: nil,
                              requested_reviewers: [.init(login: "ana")], checks: "FAILURE", verdicts: ["APPROVED", "CHANGES_REQUESTED"])
        let said = AgentContextText.pulls(identifier: "ENG-12", open: [open], merged: [],
                                          repositories: [(name: "acme/app", readAt: now.addingTimeInterval(-240)), (name: "acme/api", readAt: nil)], now: now)
        XCTAssertTrue(said.contains("#12 Export CSV: open, branch sam/eng-12, by sam, checks FAIL, changes requested, review asked of ana"))
        XCTAssertTrue(said.contains("(acme/app: read from GitHub 4 min ago.)"))
        XCTAssertTrue(said.contains("(acme/api: not read by Dever yet"))
        XCTAssertTrue(AgentContextText.pulls(identifier: "ENG-12", open: [], merged: [], repositories: [(name: "acme/app", readAt: now)], now: now)
            .hasPrefix("No pull request found for ENG-12"))
        XCTAssertEqual(AgentContextText.pulls(identifier: "ENG-12", open: [], merged: [], repositories: [], now: now),
                       "The project of ENG-12 follows no repository in Dever.")

        // The brief promises the tools only when the agent has them.
        XCTAssertTrue(AgentBrief.text(identifier: "ENG-1", title: "T", url: "u", branch: nil, description: nil, tools: true).contains("the dever tools, with ENG-1"))
        XCTAssertFalse(AgentBrief.text(identifier: "ENG-1", title: "T", url: "u", branch: nil, description: nil).contains("dever tools"))
    }

    func testThePluginsVersionIsReadFromEachToolsList() {
        let claude = """
        Installed plugins:

          ❯ dever@dever
            Version: 1.0.0
            Scope: user
            Status: ✔ enabled
        """
        XCTAssertEqual(AgentPlugin.installedVersion(.claudeCode, list: claude), "1.0.0")
        XCTAssertNil(AgentPlugin.installedVersion(.claudeCode, list: "Installed plugins:\n\n  ❯ other@market\n    Version: 3.0.0"))
        let codex = """
        PLUGIN       STATUS              VERSION  SOURCE
        other@market installed, enabled  2.0.0    /somewhere
        dever@dever  installed, enabled  1.1.0    /Users/someone/agent/codex-plugin/plugins/dever
        """
        XCTAssertEqual(AgentPlugin.installedVersion(.codex, list: codex), "1.1.0")
        XCTAssertNil(AgentPlugin.installedVersion(.codex, list: "dever@dever  available  1.1.0  /x"))
    }

    func testAProposalNeedsASummaryAndWritesNothingByItself() {
        let now = Date(timeIntervalSince1970: 1_794_571_200)
        XCTAssertNil(AgentProposal(tool: .codex, arguments: ["issue": "ENG-1"], at: now))
        XCTAssertNil(AgentProposal(tool: .codex, arguments: ["summary": "done"], at: now))
        var proposal = AgentProposal(tool: .codex, arguments: ["issue": " ENG-1 ", "summary": "Done.", "status": "review", "reply": "  ", "not_verified": "big files"], at: now)!
        XCTAssertEqual(proposal.identifier, "ENG-1")
        XCTAssertNil(proposal.reply)
        XCTAssertEqual(proposal.notVerified, "big files")
        XCTAssertTrue(proposal.pending)
        // The state it names is found by its name, exact first, else contained.
        func state(_ name: String) -> LinearTeamContext.WorkflowState { .init(id: name, name: name, type: "started", color: "", position: 0) }
        let states = [state("In Progress"), state("Code review"), state("In Review"), state("Done")]
        XCTAssertEqual(proposal.state(in: states)?.name, "Code review")
        proposal.status = "in review"
        XCTAssertEqual(proposal.state(in: states)?.name, "In Review")
        proposal.status = "Shipped"
        XCTAssertNil(proposal.state(in: states))
        proposal.statusDismissed = true
        XCTAssertFalse(proposal.pending)
    }

    func testWhatAnAgentAsksOfTheDeveloper() {
        let now = Date(timeIntervalSince1970: 1_794_571_200)
        func session(_ state: AgentSession.State) -> AgentSession {
            AgentSession(id: "s", tool: .codex, cwd: nil, branch: "b", state: state, sentence: nil, since: now, heard: now)
        }
        let proposal = AgentProposal(tool: .codex, arguments: ["issue": "ENG-1", "summary": "Done."], at: now)
        XCTAssertEqual(AgentAttention.of(session: session(.waiting), proposal: proposal, reviewed: false), .waiting)
        XCTAssertEqual(AgentAttention.of(session: session(.working), proposal: proposal, reviewed: true), .finished)
        XCTAssertEqual(AgentAttention.of(session: session(.finished), proposal: nil, reviewed: false), .finished)
        XCTAssertNil(AgentAttention.of(session: session(.finished), proposal: nil, reviewed: true))
        XCTAssertNil(AgentAttention.of(session: session(.working), proposal: nil, reviewed: false))
        XCTAssertNil(AgentAttention.of(session: nil, proposal: nil, reviewed: false))
    }

    func testAcceptanceCriteriaAreReadFromTheDescription() {
        let described = """
        ## Why
        - Because people ask.

        ## Acceptance criteria
        - [ ] Export respects the active filters
        - [x] Dates in the workspace time zone
        1. A file over 50k rows still opens

        ## Notes
        - Not a criterion
        """
        XCTAssertEqual(AcceptanceCriteria.parse(described),
                       ["Export respects the active filters", "Dates in the workspace time zone", "A file over 50k rows still opens"])
        XCTAssertEqual(AcceptanceCriteria.parse("**Critères d'acceptation**\n* Le bouton est visible\n* Le fichier se télécharge"),
                       ["Le bouton est visible", "Le fichier se télécharge"])
        // No heading names them: the task list.
        XCTAssertEqual(AcceptanceCriteria.parse("Do this.\n- [ ] One\n- plain\n- [x] Two"), ["One", "Two"])
        XCTAssertEqual(AcceptanceCriteria.parse("Just words.\n- a list\n- of things"), [])
        XCTAssertEqual(AcceptanceCriteria.parse(nil), [])
    }

    func testAnAgentThatWaitsOrFinishedComesFirstInDelivery() {
        let now = Date(timeIntervalSince1970: 1_794_571_200)
        func issue(_ n: Int, _ type: String, mine: Bool = true) -> LinearIssue {
            LinearIssue(id: "i\(n)", identifier: "ENG-\(n)", title: "T\(n)", url: "", updatedAt: "2026-11-01T00:00:00.000Z",
                        state: .init(id: nil, name: type == "started" ? "In Progress" : "Todo", type: type, color: nil),
                        assignee: mine ? .init(id: "me", name: "Me", avatarUrl: nil) : nil, branchName: "b\(n)", attachments: nil,
                        priority: 3, dueDate: nil, labels: nil, archivedAt: nil)
        }
        let failing = DeliveryPlan.Pull(number: 9, title: "P", url: "", repository: "a/b", author: "me", pipeline: .failing)
        let viewer = DeliveryPlan.Viewer(linearID: "me", linearName: "Me", githubLogin: "me")
        let issues = [issue(1, "started"), issue(2, "unstarted"), issue(3, "started"), issue(4, "unstarted", mine: false)]
        let plan = DeliveryPlan(issues: issues, open: ["ENG-1": [failing]], merged: [:], blockers: [:], viewer: viewer,
                                agents: ["ENG-2": .finished, "ENG-3": .waiting, "ENG-4": .waiting], now: now)
        // The agents are apart, waiting first; an agent of the viewer's on an unassigned issue counts as theirs.
        XCTAssertEqual(plan.agents.map(\.issue.identifier), ["ENG-3", "ENG-4", "ENG-2"])
        XCTAssertEqual(plan.agents.map(\.situation), [.agentWaiting, .agentWaiting, .agentFinished])
        XCTAssertEqual(plan.yours, 4)
        // Start here stays the viewer's own next task.
        XCTAssertEqual(plan.start?.issue.identifier, "ENG-1")
        XCTAssertEqual(plan.start?.situation, .ciFailed)
        XCTAssertTrue(plan.next.isEmpty)
        // "Finished" does not hide a broken pipeline.
        let broken = DeliveryPlan(issues: [issue(1, "started")], open: ["ENG-1": [failing]], merged: [:], blockers: [:], viewer: viewer,
                                  agents: ["ENG-1": .finished], now: now)
        XCTAssertEqual(broken.start?.situation, .ciFailed)
        XCTAssertTrue(DeliveryPlan.Situation.agentFinished.actionable)
    }

    func testTheEndOfATurnRemindsTheAgentOnceToLeaveItsAccount() throws {
        let now = Date(timeIntervalSince1970: 1_794_571_200)
        func stop(active: Bool? = nil) -> AgentEvent {
            let flag = active.map { ", \"stop_hook_active\": \($0)" } ?? ""
            return try! JSONDecoder().decode(AgentEvent.self, from: Data("{\"hook_event_name\": \"Stop\", \"session_id\": \"s\"\(flag)}".utf8))
        }
        XCTAssertTrue(AgentReminder.needed(event: stop(), contextOn: true, issue: "ENG-1", reminded: false, proposalAt: nil, sessionStart: now))
        // Already continued by a Stop hook, tools off, no known issue, already reminded: nothing.
        XCTAssertFalse(AgentReminder.needed(event: stop(active: true), contextOn: true, issue: "ENG-1", reminded: false, proposalAt: nil, sessionStart: now))
        XCTAssertFalse(AgentReminder.needed(event: stop(), contextOn: false, issue: "ENG-1", reminded: false, proposalAt: nil, sessionStart: now))
        XCTAssertFalse(AgentReminder.needed(event: stop(), contextOn: true, issue: nil, reminded: false, proposalAt: nil, sessionStart: now))
        XCTAssertFalse(AgentReminder.needed(event: stop(), contextOn: true, issue: "ENG-1", reminded: true, proposalAt: nil, sessionStart: now))
        // A proposal left in this session: nothing; one left before it began does not count.
        XCTAssertFalse(AgentReminder.needed(event: stop(), contextOn: true, issue: "ENG-1", reminded: false, proposalAt: now.addingTimeInterval(60), sessionStart: now))
        XCTAssertTrue(AgentReminder.needed(event: stop(), contextOn: true, issue: "ENG-1", reminded: false, proposalAt: now.addingTimeInterval(-60), sessionStart: now))
        // Only a Stop.
        let other = try JSONDecoder().decode(AgentEvent.self, from: Data(#"{"hook_event_name": "PostToolUse", "session_id": "s"}"#.utf8))
        XCTAssertFalse(AgentReminder.needed(event: other, contextOn: true, issue: "ENG-1", reminded: false, proposalAt: nil, sessionStart: now))
        // The output both tools read as "continue with this instruction".
        let output = try XCTUnwrap(JSONSerialization.jsonObject(with: AgentReminder.output(identifier: "ENG-1")) as? [String: String])
        XCTAssertEqual(output["decision"], "block")
        XCTAssertTrue(output["reason"]?.contains("propose_update") == true)
        XCTAssertTrue(output["reason"]?.contains("ENG-1") == true)
        XCTAssertTrue(AgentPlugin.hookScript.contains("printf"))
    }

    func testAnAgentsUsageReportIsReadOnlyFromItsFigures() throws {
        let now = Date(timeIntervalSince1970: 1_794_571_200)
        // Numbers may come as numbers: they are read as their text.
        let request = #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"report_usage","arguments":{"issue":"","five_hour_used":38,"five_hour_resets":"2026-11-13T14:10:00Z","week_used":"20%","plan":"Team","flag":true}}}"#
        guard case .call(let call)? = AgentMCP.read(Data(request.utf8))?.request else { return XCTFail("not a call") }
        XCTAssertEqual(call.arguments["five_hour_used"], "38")
        XCTAssertNil(call.arguments["flag"])
        let usage = try XCTUnwrap(AgentUsage.reported(call.arguments, at: now))
        XCTAssertEqual(usage.windows.map(\.minutes), [300, 10_080])
        XCTAssertEqual(usage.windows.map(\.leftPercent), [62, 80])
        XCTAssertEqual(usage.windows[0].resetsAt, Date(timeIntervalSince1970: 1_794_579_000))
        XCTAssertNil(usage.windows[1].resetsAt)
        XCTAssertEqual(usage.plan, "Team")
        XCTAssertFalse(usage.limitReached)
        XCTAssertTrue(try XCTUnwrap(AgentUsage.reported(["five_hour_used": "100"], at: now)).limitReached)
        XCTAssertEqual(try XCTUnwrap(AgentUsage.reported(["week_used": "140"], at: now)).windows[0].leftPercent, 0)
        // No figure, no reading.
        XCTAssertNil(AgentUsage.reported(["plan": "Team", "five_hour_used": "soon"], at: now))
        XCTAssertTrue(AgentPlugin.skill.contains("report_usage"))
        XCTAssertTrue(AgentReminder.reason(identifier: "ENG-1").contains("report_usage"))
    }
}
