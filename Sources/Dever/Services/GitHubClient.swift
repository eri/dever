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
    /// The rollup of the head commit's checks, as GitHub shows it on the pull request:
    /// SUCCESS, FAILURE, ERROR, PENDING or EXPECTED; nil when the commit has no checks.
    var checks: String?
    /// Each reviewer's latest verdict: APPROVED or CHANGES_REQUESTED.
    var verdicts: [String]?
}

/// What one request tells about a repository: its open pull requests with their checks and
/// reviews, and the health of its default branch.
struct GitHubRepositoryState {
    var pulls: [GitHubPull]
    var defaultBranch: String?
    /// The rollup of the default branch's head commit (see `GitHubPull.checks`).
    var defaultBranchChecks: String?
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

/// The last body of each GET with the ETag GitHub gave for it. A GET sent with that ETag comes
/// back 304 when nothing changed: no download, and it does not count against the rate limit.
private final class GitHubETags: @unchecked Sendable {
    static let shared = GitHubETags()
    private let lock = NSLock()
    private var entries: [String: (etag: String, data: Data)] = [:]

    subscript(key: String) -> (etag: String, data: Data)? {
        get { lock.lock(); defer { lock.unlock() }; return entries[key] }
        set {
            lock.lock(); defer { lock.unlock() }
            // A few hundred small bodies at most; start over rather than track what is oldest.
            if entries.count > 300 { entries.removeAll() }
            entries[key] = newValue
        }
    }
}

struct GitHubClient {
    var token: String

    func get<T: Decodable>(_ path: String, as: T.Type = T.self) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await send("GET", path))
    }

    /// Any verb with a JSON body; returns the raw response (some endpoints answer 204).
    /// A GET is conditional on the ETag of its last answer.
    @discardableResult
    func send(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> Data {
        // URLSession's own cache would serve a GET for a minute without asking GitHub.
        var req = URLRequest(url: URL(string: "https://api.github.com" + path)!, cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let cacheKey = "\(token.hashValue) \(path)"
        let known = method == "GET" ? GitHubETags.shared[cacheKey] : nil
        if let known { req.setValue(known.etag, forHTTPHeaderField: "If-None-Match") }
        let started = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        RequestLog.record("github", "\(method) \(path)", status: code, bytes: data.count, since: started)
        if code == 304, let known { return known.data }
        if code == 401 { throw AppError.unauthorized(.github) }
        guard (200..<300).contains(code) else {
            throw AppError.message("GitHub \(code): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        if method == "GET", let etag = http?.value(forHTTPHeaderField: "ETag"), data.count < 2_000_000 {
            GitHubETags.shared[cacheKey] = (etag, data)
        }
        return data
    }

    /// One GraphQL query: a few kilobytes for what the REST lists answer in megabytes.
    func graphql<T: Decodable>(_ query: String, variables: [String: Any], as: T.Type = T.self) async throws -> T {
        let data = try await send("POST", "/graphql", json: ["query": query, "variables": variables])
        if let errors = try? JSONDecoder().decode(GraphQLFailure.self, from: data).errors, let first = errors.first {
            throw AppError.message("GitHub: \(first.message)")
        }
        return try JSONDecoder().decode(GraphQLEnvelope<T>.self, from: data).data
    }

    private struct GraphQLFailure: Decodable { struct E: Decodable { var message: String }; var errors: [E]? }
    private struct GraphQLEnvelope<T: Decodable>: Decodable { var data: T }

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

    private struct PullNode: Decodable {
        struct Author: Decodable { var login: String }
        struct Requests: Decodable {
            /// A team asked to review has no login: only people are kept.
            struct Reviewer: Decodable { var login: String? }
            struct Node: Decodable { var requestedReviewer: Reviewer? }
            var nodes: [Node]
        }
        struct Reviews: Decodable {
            struct Node: Decodable { var state: String }
            var nodes: [Node]
        }
        struct Commits: Decodable {
            struct Rollup: Decodable { var state: String }
            struct Commit: Decodable { var statusCheckRollup: Rollup? }
            struct Node: Decodable { var commit: Commit }
            var nodes: [Node]
        }
        var databaseId: Int?
        var number: Int
        var title: String
        var url: String
        var isDraft: Bool?
        var updatedAt: String
        var mergedAt: String?
        var headRefName: String
        var author: Author?
        var reviewRequests: Requests?
        var latestOpinionatedReviews: Reviews?
        var commits: Commits?

        var pull: GitHubPull {
            GitHubPull(id: databaseId ?? number, number: number, title: title, html_url: url, draft: isDraft,
                       // A deleted account has no author: GitHub shows it as "ghost".
                       user: .init(login: author?.login ?? "ghost"), updated_at: updatedAt,
                       head: .init(ref: headRefName), merged_at: mergedAt,
                       requested_reviewers: reviewRequests?.nodes.compactMap { $0.requestedReviewer?.login.map { .init(login: $0) } },
                       checks: commits?.nodes.first?.commit.statusCheckRollup?.state,
                       verdicts: latestOpinionatedReviews?.nodes.map(\.state))
        }
    }

    private struct PullPage: Decodable {
        struct Info: Decodable { var hasNextPage: Bool; var endCursor: String? }
        var pageInfo: Info
        var nodes: [PullNode]
    }

    private static func split(_ repo: String) -> [String: Any] {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        return ["owner": parts.first ?? "", "name": parts.count > 1 ? parts[1] : ""]
    }

    /// The repository's open pull requests, most recently updated first (up to 300), each with
    /// the checks of its head commit, its reviewers' verdicts and who is asked to review; and
    /// the default branch with its checks.
    func repository(_ repo: String) async throws -> GitHubRepositoryState {
        struct R: Decodable {
            struct Repo: Decodable {
                struct Branch: Decodable {
                    struct Target: Decodable { var statusCheckRollup: PullNode.Commits.Rollup? }
                    var name: String
                    var target: Target?
                }
                var defaultBranchRef: Branch?
                var pullRequests: PullPage
            }
            var repository: Repo?
        }
        var state = GitHubRepositoryState(pulls: [])
        var variables = Self.split(repo)
        for page in 0..<3 {
            guard let r = try await graphql("""
            query($owner: String!, $name: String!, $after: String) { repository(owner: $owner, name: $name) {
              defaultBranchRef { name target { ... on Commit { statusCheckRollup { state } } } }
              pullRequests(states: OPEN, first: 100, after: $after, orderBy: { field: UPDATED_AT, direction: DESC }) {
                pageInfo { hasNextPage endCursor }
                nodes { databaseId number title url isDraft updatedAt headRefName author { login }
                  reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } } } }
                  latestOpinionatedReviews(first: 20) { nodes { state } }
                  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } } }
            """, variables: variables, as: R.self).repository else {
                throw AppError.message("GitHub: \(repo) not found, or this account cannot see it")
            }
            if page == 0 {
                state.defaultBranch = r.defaultBranchRef?.name
                state.defaultBranchChecks = r.defaultBranchRef?.target?.statusCheckRollup?.state
            }
            state.pulls += r.pullRequests.nodes.map(\.pull)
            guard r.pullRequests.pageInfo.hasNextPage, let cursor = r.pullRequests.pageInfo.endCursor else { break }
            variables["after"] = cursor
        }
        return state
    }

    /// Open pull requests, most recently updated first (up to 300).
    func pulls(_ repo: String) async throws -> [GitHubPull] {
        try await repository(repo).pulls
    }

    /// Pull requests merged recently, newest first (the 200 last touched).
    func mergedPulls(_ repo: String) async throws -> [GitHubPull] {
        struct R: Decodable {
            struct Repo: Decodable { var pullRequests: PullPage }
            var repository: Repo?
        }
        var all: [GitHubPull] = []
        var variables = Self.split(repo)
        for _ in 0..<2 {
            guard let page = try await graphql("""
            query($owner: String!, $name: String!, $after: String) { repository(owner: $owner, name: $name) {
              pullRequests(states: MERGED, first: 100, after: $after, orderBy: { field: UPDATED_AT, direction: DESC }) {
                pageInfo { hasNextPage endCursor }
                nodes { databaseId number title url updatedAt mergedAt headRefName author { login } } } } }
            """, variables: variables, as: R.self).repository?.pullRequests else { break }
            all += page.nodes.map(\.pull)
            guard page.pageInfo.hasNextPage, let cursor = page.pageInfo.endCursor else { break }
            variables["after"] = cursor
        }
        return all.sorted { ($0.merged_at ?? "") > ($1.merged_at ?? "") }
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
