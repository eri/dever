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
    struct Head: Codable { var ref: String }
    var id: Int
    var number: Int
    var title: String
    var html_url: String
    var draft: Bool?
    var user: User
    var updated_at: String
    var head: Head
    var merged_at: String?
    /// People whose review is asked for and not given yet.
    var requested_reviewers: [User]?
}

/// One review of a pull request: APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED or PENDING.
struct GitHubReview: Codable {
    var user: GitHubPull.User?
    var state: String
}

struct GitHubRun: Codable, Identifiable {
    var id: Int
    var name: String?
    var head_branch: String?
    var status: String?
    var conclusion: String?
    var html_url: String
    var created_at: String
    /// What started the run: issue_comment, pull_request, workflow_dispatch, schedule…
    var event: String?
    var updated_at: String?
    var actor: GitHubPull.User?
}

/// One pull request in full: its state, its head and its labels, with its comment count
/// (which page of comments is the last one).
struct GitHubPullDetail: Codable {
    struct Head: Codable { var ref: String; var sha: String }
    struct Label: Codable { var name: String }
    var number: Int
    var title: String
    var html_url: String
    var state: String
    var draft: Bool?
    var user: GitHubPull.User
    var head: Head
    var labels: [Label]
    var comments: Int
    var merged_at: String?
    var closed_at: String?
    var updated_at: String
}

struct GitHubComment: Codable, Identifiable {
    var id: Int
    var body: String?
    var user: GitHubPull.User
    var created_at: String
    var html_url: String
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
        try JSONDecoder().decode(T.self, from: try await send("GET", path))
    }

    /// Any verb with a JSON body; returns the raw response (some endpoints answer 204).
    @discardableResult
    func send(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw AppError.unauthorized(.github) }
        guard (200..<300).contains(code) else {
            throw AppError.message("GitHub \(code): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        return data
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

    /// Open pull requests, most recently updated first (up to 300).
    func pulls(_ repo: String) async throws -> [GitHubPull] {
        var all: [GitHubPull] = []
        for page in 1...3 {
            let batch: [GitHubPull] = try await get(
                "/repos/\(repo)/pulls?state=open&sort=updated&direction=desc&per_page=100&page=\(page)")
            all += batch
            if batch.count < 100 { break }
        }
        return all
    }

    /// Pull requests merged recently, newest first (scans the last 300 closed ones).
    func mergedPulls(_ repo: String) async throws -> [GitHubPull] {
        var all: [GitHubPull] = []
        for page in 1...3 {
            let batch: [GitHubPull] = try await get(
                "/repos/\(repo)/pulls?state=closed&sort=updated&direction=desc&per_page=100&page=\(page)")
            all += batch.filter { $0.merged_at != nil }
            if batch.count < 100 { break }
        }
        return all.sorted { ($0.merged_at ?? "") > ($1.merged_at ?? "") }
    }

    /// The reviews of a pull request, oldest first (the first hundred).
    func reviews(_ repo: String, number: Int) async throws -> [GitHubReview] {
        try await get("/repos/\(repo)/pulls/\(number)/reviews?per_page=100")
    }

    func runs(_ repo: String, branch: String? = nil) async throws -> [GitHubRun] {
        struct R: Decodable { var workflow_runs: [GitHubRun] }
        var path = "/repos/\(repo)/actions/runs?per_page=100"
        if let branch, let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&branch=\(encoded)"
        }
        return try await get(path, as: R.self).workflow_runs
    }

    func defaultBranch(_ repo: String) async throws -> String {
        struct R: Decodable { var default_branch: String }
        return try await get("/repos/\(repo)", as: R.self).default_branch
    }

    // MARK: Preview environments (one pull request)

    func pull(_ repo: String, number: Int) async throws -> GitHubPullDetail {
        try await get("/repos/\(repo)/pulls/\(number)")
    }

    /// The newest comments of a pull request: only the last page (GitHub lists them oldest
    /// first), `total` being the PR's comment count.
    func latestComments(_ repo: String, number: Int, total: Int) async throws -> [GitHubComment] {
        let perPage = 100
        let page = max(1, (total + perPage - 1) / perPage)
        var out: [GitHubComment] = try await get("/repos/\(repo)/issues/\(number)/comments?per_page=\(perPage)&page=\(page)")
        // A short last page gets the page before it, so a status comment is not missed.
        if out.count < 20, page > 1 {
            let earlier: [GitHubComment] = try await get("/repos/\(repo)/issues/\(number)/comments?per_page=\(perPage)&page=\(page - 1)")
            out = earlier + out
        }
        return out
    }

    func comment(_ repo: String, number: Int, body: String) async throws -> GitHubComment {
        try JSONDecoder().decode(GitHubComment.self,
                                 from: try await send("POST", "/repos/\(repo)/issues/\(number)/comments", json: ["body": body]))
    }

    /// The latest runs of one workflow file, newest first; `branch` narrows to a head branch.
    func workflowRuns(_ repo: String, file: String, branch: String? = nil, limit: Int = 10) async throws -> [GitHubRun] {
        struct R: Decodable { var workflow_runs: [GitHubRun] }
        var path = "/repos/\(repo)/actions/workflows/\(file)/runs?per_page=\(limit)"
        if let branch, let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&branch=\(encoded)"
        }
        return try await get(path, as: R.self).workflow_runs
    }

    /// The jobs of a run: the one in progress names the step being run.
    func runSteps(_ repo: String, runID: Int) async throws -> (job: String, step: String)? {
        struct Step: Decodable { var name: String; var status: String }
        struct Job: Decodable { var name: String; var status: String; var steps: [Step]? }
        struct R: Decodable { var jobs: [Job] }
        let jobs = try await get("/repos/\(repo)/actions/runs/\(runID)/jobs?per_page=50", as: R.self).jobs
        guard let job = jobs.first(where: { $0.status == "in_progress" }) ?? jobs.first(where: { $0.status == "queued" }) else { return nil }
        let step = job.steps?.first(where: { $0.status == "in_progress" })?.name
        return (job.name, step ?? job.name)
    }

    /// Starts a workflow by hand (`workflow_dispatch`) on `ref` with its inputs.
    func dispatch(_ repo: String, file: String, ref: String, inputs: [String: String]) async throws {
        try await send("POST", "/repos/\(repo)/actions/workflows/\(file)/dispatches", json: ["ref": ref, "inputs": inputs])
    }

    /// Whether a host answers at all: any HTTP status counts, a timeout or a refused
    /// connection does not. HEAD, so nothing is downloaded.
    static func isReachable(_ url: URL, timeout: TimeInterval = 5) async -> Bool {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "HEAD"
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse).map { $0.statusCode < 500 } ?? false
    }
}
