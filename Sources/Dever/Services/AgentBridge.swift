import Foundation
import Network

/// Dever's local listener for the coding agents: the tools' hooks post here, on the loopback
/// interface only, with a token made at each launch. The port and the token are written to a
/// file only this user can read, which the hook command reads. Nothing is served to anything else,
/// and a request without the token is dropped.
final class AgentBridge: @unchecked Sendable {
    static let shared = AgentBridge()

    /// `~/Library/Application Support/Dever/agent`: the hook command, the plugins, and `bridge.json`.
    static var folder: URL {
        // Tests point it elsewhere, so they never touch the folder of a Dever that is running.
        if let path = ProcessInfo.processInfo.environment["DEVER_AGENT_FOLDER"] { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dever/agent", isDirectory: true)
    }
    static var address: URL { folder.appendingPathComponent("bridge.json") }

    private let queue = DispatchQueue(label: "io.github.eri.dever.agent-bridge")
    private var listener: NWListener?
    private var token = ""
    /// A hook's payload can carry a tool's whole output; past this the connection is dropped.
    private static let limit = 8 * 1_048_576

    func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            guard let listener = try? NWListener(using: parameters) else { return }
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                if case .ready = state, let port = listener?.port?.rawValue { self?.publish(port: port) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: self.queue)
                self.read(connection, Data())
            }
            listener.start(queue: queue)
        }
    }

    /// Where the hook command finds Dever: readable by this user only, rewritten at each launch.
    private func publish(port: UInt16) {
        let body = "{\"port\": \(port), \"token\": \"\(token)\"}\n"
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.address.path, contents: Data(body.utf8), attributes: [.posixPermissions: 0o600])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.address.path)
    }

    private func read(_ connection: NWConnection, _ received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, done, error in
            guard let self else { return connection.cancel() }
            var buffer = received
            if let data { buffer.append(data) }
            switch BridgeRequest.parse(buffer) {
            case .request(let method, let path, let bearer, let body):
                let parts = path.split(separator: "/")
                // `POST /mcp/<tool>` with the token: a question from the agent, answered from the stores.
                if method == "POST", parts.count == 2, parts[0] == "mcp", bearer == self.token, !self.token.isEmpty,
                   let tool = AgentTool(rawValue: String(parts[1])) {
                    Task { @MainActor in
                        let answer = await AgentContextServer.answer(body, tool: tool)
                        let head = answer == nil ? "HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                            : "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(answer!.count)\r\nConnection: close\r\n\r\n"
                        connection.send(content: Data(head.utf8) + (answer ?? Data()), completion: .contentProcessed { _ in connection.cancel() })
                    }
                    return
                }
                let status = self.handle(method: method, path: path, bearer: bearer, body: body)
                let answer = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(answer.utf8), completion: .contentProcessed { _ in connection.cancel() })
            case .malformed:
                connection.cancel()
            case .incomplete:
                if done || error != nil || buffer.count > Self.limit { connection.cancel() } else { self.read(connection, buffer) }
            }
        }
    }

    /// `POST /hook/<tool>` with the token: one hook call.
    private func handle(method: String, path: String, bearer: String?, body: Data) -> String {
        guard bearer == token, !token.isEmpty else { return "401 Unauthorized" }
        let parts = path.split(separator: "/")
        guard method == "POST", parts.count == 2, parts[0] == "hook", let tool = AgentTool(rawValue: String(parts[1])) else {
            return "404 Not Found"
        }
        guard let event = try? JSONDecoder().decode(AgentEvent.self, from: body) else { return "400 Bad Request" }
        Task { @MainActor in AgentStore.shared.receive(event, tool: tool) }
        return "204 No Content"
    }
}
