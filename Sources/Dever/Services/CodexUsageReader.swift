import Foundation

/// Why Codex's usage could not be read.
enum CodexUsageError: LocalizedError, Equatable {
    case notInstalled
    /// Signed in with an API key: billed per token, no plan window to show.
    case noPlan
    /// Codex's own sign-in has expired: Codex itself must be opened to sign in again.
    case signInExpired(String)
    case failed(String)

    /// One short sentence; what the tool said, word for word, is in `detail`.
    var errorDescription: String? {
        switch self {
        case .notInstalled: "Codex is not installed"
        case .noPlan: "Billed per token: no plan limit"
        case .signInExpired: "Codex's sign-in has expired: open Codex to sign in again"
        case .failed: "Codex could not say what is left"
        }
    }

    /// What the tool said, for the "Details" under the sentence.
    var detail: String? {
        switch self {
        case .signInExpired(let message), .failed(let message): message
        default: nil
        }
    }

    /// The tool's refusal, read as what it means.
    static func from(message: String) -> CodexUsageError {
        let text = message.lowercased()
        if text.contains("chatgpt authentication required") { return .noPlan }
        if text.contains("token_expired") || text.contains("token has expired") || text.contains("401") { return .signInExpired(message) }
        return .failed(message)
    }
}

/// Asks Codex itself what is left of the plan: its own binary, run as its app server for one
/// question (`account/rateLimits/read`, documented), then ended. No session, no model call, and
/// Dever never sees the login: the tool uses the one the user already made. About two seconds.
enum CodexUsageReader {
    /// Where the desktop app has kept its binary, newest layout first: it moved between versions.
    static let bundled = ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex"]

    /// The binary inside the desktop app, else one where package managers put it.
    static func binary(app: URL?) -> URL? {
        let candidates = bundled.compactMap { app?.appendingPathComponent($0).path } + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return candidates.first(where: FileManager.default.isExecutableFile).map { URL(fileURLWithPath: $0) }
    }

    static func read(binary: URL, timeout: TimeInterval = 12) async throws -> AgentUsage {
        try await Task.detached(priority: .utility) { try ask(binary: binary, timeout: timeout) }.value
    }

    private static func ask(binary: URL, timeout: TimeInterval) throws -> AgentUsage {
        let process = Process()
        process.executableURL = binary
        // An approval policy this version refuses in the user's config stops the server at start;
        // the question needs no policy, so a valid one is passed for this run only.
        process.arguments = ["-c", "approval_policy=\"on-request\"", "app-server"]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch { throw CodexUsageError.failed(error.localizedDescription) }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            if process.isRunning { process.terminate() }
        }

        func send(_ message: [String: Any]) {
            guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
            data.append(0x0A)
            try? input.fileHandleForWriting.write(contentsOf: data)
        }
        var buffer = Data()
        /// The answer to request `id`: its `result` as data, or the tool's error message.
        func answer(to id: Int) throws -> Data {
            while true {
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          (message["id"] as? Int) == id else { continue }
                    if let error = message["error"] as? [String: Any] {
                        throw CodexUsageError.from(message: error["message"] as? String ?? "an error without words")
                    }
                    guard let result = message["result"], let data = try? JSONSerialization.data(withJSONObject: result) else {
                        throw CodexUsageError.failed("an answer without a result")
                    }
                    return data
                }
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty {
                    // The server ended (or the deadline ended it): its last words say why.
                    let said = String(decoding: errors.fileHandleForReading.availableData, as: UTF8.self)
                        .split(whereSeparator: \.isNewline).last.map(String.init)
                    throw CodexUsageError.failed(said ?? "no answer")
                }
                buffer.append(chunk)
            }
        }

        send(["id": 1, "method": "initialize",
              "params": ["clientInfo": ["name": "dever", "title": "Dever", "version": "1"]]])
        _ = try answer(to: 1)
        send(["method": "initialized"])
        send(["id": 2, "method": "account/rateLimits/read", "params": ["excludeResetCreditDetails": true]])
        let result = try answer(to: 2)
        do { return try AgentUsage.codex(result: result, at: Date()) }
        catch { throw CodexUsageError.failed("an answer Dever does not understand") }
    }
}
