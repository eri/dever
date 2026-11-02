import Foundation

struct GitHubCredentials: Codable {
    var token: String
    var login: String
}

struct GitHubRepo: Codable, Identifiable, Hashable {
    var id: Int
    var full_name: String
    var html_url: String
    var `private`: Bool
    var pushed_at: String?
}

struct GitHubPull: Codable, Identifiable {
    struct User: Codable { var login: String }
    var id: Int
    var number: Int
    var title: String
    var html_url: String
    var draft: Bool?
    var user: User
    var updated_at: String
}

struct GitHubRun: Codable, Identifiable {
    var id: Int
    var name: String?
    var head_branch: String?
    var status: String?
    var conclusion: String?
    var html_url: String
    var created_at: String
}

/// GitHub: OAuth Device Flow with a public OAuth client (GitHub CLI's by default).
/// No key to create, and GitHub OAuth tokens never expire unless revoked.
/// Alternative: reuse the existing `gh` session.
enum GitHubAuth {
    /// The team's OAuth client if configured (dever.json), otherwise GitHub CLI's public one.
    static var clientID: String { DeverConfig.shared.github?.clientID ?? "178c6fc778ccc68e1d6a" }
    static let scopes = "repo read:org workflow"

    struct DeviceCode: Decodable {
        var device_code: String
        var user_code: String
        var verification_uri: String
        var interval: Int
        var expires_in: Int
    }

    static func startDeviceFlow() async throws -> DeviceCode {
        var req = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = form(["client_id": clientID, "scope": scopes])
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }

    static func pollToken(_ code: DeviceCode) async throws -> String {
        var interval = UInt64(max(code.interval, 5))
        let deadline = Date().addingTimeInterval(TimeInterval(code.expires_in))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: interval * 1_000_000_000)
            var req = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.httpBody = form([
                "client_id": clientID,
                "device_code": code.device_code,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            let (data, _) = try await URLSession.shared.data(for: req)
            let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if let token = obj["access_token"] as? String { return token }
            switch obj["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case let err?: throw AppError.message("GitHub: \(err)")
            case nil: throw AppError.message("Unexpected GitHub response")
            }
        }
        throw AppError.message("GitHub code expired, please try again.")
    }

    /// Reuses the GitHub CLI token when the user is already signed in with `gh`.
    static func tokenFromGhCLI() throws -> String {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        guard let gh = candidates.first(where: FileManager.default.isExecutableFile) else {
            throw AppError.message("GitHub CLI (gh) not found")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gh)
        p.arguments = ["auth", "token"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        let token = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.terminationStatus == 0, !token.isEmpty else {
            throw AppError.message("`gh auth token` failed — run `gh auth login` first")
        }
        return token
    }

    private static func form(_ params: [String: String]) -> Data {
        var c = URLComponents()
        c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((c.percentEncodedQuery ?? "").utf8)
    }
}

struct GitHubClient {
    var token: String

    func get<T: Decodable>(_ path: String, as: T.Type = T.self) async throws -> T {
        var req = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw AppError.unauthorized(.github) }
        guard (200..<300).contains(code) else {
            throw AppError.message("GitHub \(code): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func viewerLogin() async throws -> String {
        struct U: Decodable { var login: String }
        return try await get("/user", as: U.self).login
    }

    func repos() async throws -> [GitHubRepo] {
        var all: [GitHubRepo] = []
        for page in 1...5 {
            let batch: [GitHubRepo] = try await get(
                "/user/repos?per_page=100&sort=pushed&affiliation=owner,collaborator,organization_member&page=\(page)")
            all += batch
            if batch.count < 100 { break }
        }
        return all
    }

    func pulls(_ repo: String) async throws -> [GitHubPull] {
        try await get("/repos/\(repo)/pulls?state=open&per_page=30")
    }

    func runs(_ repo: String, branch: String? = nil) async throws -> [GitHubRun] {
        struct R: Decodable { var workflow_runs: [GitHubRun] }
        var path = "/repos/\(repo)/actions/runs?per_page=15"
        if let branch, let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&branch=\(encoded)"
        }
        return try await get(path, as: R.self).workflow_runs
    }

    func defaultBranch(_ repo: String) async throws -> String {
        struct R: Decodable { var default_branch: String }
        return try await get("/repos/\(repo)", as: R.self).default_branch
    }
}
