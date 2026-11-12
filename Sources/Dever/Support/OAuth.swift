import AppKit
import CryptoKit
import Foundation
import Network

/// Credentials of the team's "Dever" OAuth apps (created once by an admin, see docs/SETUP.md).
/// Read from the `dever.json` bundled with the app (copied by scripts/build-app.sh).
struct DeverConfig: Decodable {
    struct Slack: Decodable {
        var clientID: String
        var clientSecret: String
        /// HTTPS page (GitHub Pages) that forwards to the local server: Slack requires HTTPS.
        var redirectURL: String
    }
    struct Linear: Decodable {
        var clientID: String
    }
    struct GitHub: Decodable {
        var clientID: String?
    }

    struct Preview: Decodable {
        /// Where the team's preview environments are served: `pr-<N>-<target>.<domain>`.
        var domain: String
    }

    var slack: Slack?
    var linear: Linear?
    var github: GitHub?
    var preview: Preview?

    static let shared: DeverConfig = {
        guard let url = Bundle.main.url(forResource: "dever", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(DeverConfig.self, from: data) else {
            return DeverConfig()
        }
        return config
    }()
}

enum OAuth {
    /// Fixed port: the redirect URL must be registered verbatim in the OAuth apps.
    static let loopbackPort: UInt16 = 47321
    static func loopbackURL(_ path: String) -> String { "http://localhost:\(loopbackPort)\(path)" }

    static func randomString(_ bytes: Int = 32) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    static func pkceChallenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func form(_ params: [String: String]) -> Data {
        var c = URLComponents()
        c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }

    /// Opens `authorizeURL` in the default browser (where the user is already
    /// signed in: no captcha) and waits for the redirect on the local server.
    /// Returns the `code` once the `state` has been checked.
    static func authorize(_ authorizeURL: URL, callbackPath: String, state: String) async throws -> String {
        let server = try LoopbackServer(port: loopbackPort)
        defer { server.stop() }
        NSWorkspace.shared.open(authorizeURL)
        let query = try await server.waitForRequest(path: callbackPath, timeout: 300)
        if let error = query["error"] { throw AppError.message("Authorization denied: \(error)") }
        guard query["state"] == state else { throw AppError.message("Invalid OAuth response (state mismatch)") }
        guard let code = query["code"] else { throw AppError.message("OAuth response has no code") }
        return code
    }
}

/// Tiny HTTP server on the loopback interface that waits for a single OAuth redirect.
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "dever.oauth.loopback")
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var expectedPath = ""

    init(port: UInt16) throws {
        // Loopback interface only (127.0.0.1 and ::1): "localhost" works whichever IP the browser picks.
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            throw AppError.message("Port \(port) is busy — is another sign-in in progress?")
        }
    }

    func waitForRequest(path: String, timeout: TimeInterval) async throws -> [String: String] {
        expectedPath = path
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async {
                    self.continuation = cont
                    self.listener.newConnectionHandler = { [weak self] in self?.handle($0) }
                    self.listener.stateUpdateHandler = { [weak self] state in
                        if case .failed(let error) = state { self?.finish(.failure(error)) }
                    }
                    self.listener.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + timeout) {
                        self.finish(.failure(AppError.message("Sign-in timed out, please try again.")))
                    }
                }
            }
        } onCancel: {
            queue.async { self.finish(.failure(CancellationError())) }
        }
    }

    func stop() { listener.cancel() }

    private func finish(_ result: Result<[String: String], Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let head = String(decoding: data ?? Data(), as: UTF8.self).split(separator: "\r\n").first ?? ""
            let parts = head.split(separator: " ")
            let target = parts.count > 1 ? String(parts[1]) : "/"
            let comps = URLComponents(string: "http://localhost\(target)")
            let matches = comps?.path == self.expectedPath
            var query: [String: String] = [:]
            comps?.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
            // The page says what happened: signed in, refused by the provider, or not a sign-in at all.
            let html = OAuthPage.html(service: OAuthPage.service(path: comps?.path ?? ""),
                                      outcome: OAuthPage.outcome(matches: matches, query: query))
            let response = "HTTP/1.1 \(matches ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })
            guard matches else { return }
            self.finish(.success(query))
        }
    }
}
