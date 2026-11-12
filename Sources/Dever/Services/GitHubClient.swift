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
    /// The commit the run was started for: the pull request's head for a `pull_request` run,
    /// the default branch's for an `issue_comment` one (which says nothing of the pull request).
    var head_sha: String?
}

/// A check of a pull request's head commit that failed, as GitHub names it.
struct GitHubFailedCheck: Equatable, Sendable {
    var name: String
    /// Its page on GitHub: the job's log for an Actions job.
    var url: String
    /// The Actions job behind it, whose log can be read; nil for a check another service reports.
    var jobID: Int?
    /// The first step of the job that failed.
    var step: String?
    var completedAt: Date?
}

/// The failed checks of a pull request's head commit.
struct GitHubFailedChecks: Equatable, Sendable {
    var sha: String
    var failed: [GitHubFailedCheck]
    /// How many of the commit's other checks passed (or were skipped), and how many still run.
    var passing = 0
    var running = 0

    /// The check to explain: the Actions job that failed first (what fails after it often
    /// fails because of it), or a check without a log when there is no such job.
    var first: GitHubFailedCheck? {
        failed.filter { $0.jobID != nil }.min { ($0.completedAt ?? .distantFuture) < ($1.completedAt ?? .distantFuture) } ?? failed.first
    }
}

/// One pull request in full: its state, its head and its labels, with its comment count
/// (which page of comments is the last one).
struct GitHubPullDetail: Codable {
    struct Head: Codable { var ref: String; var sha: String }
    struct Base: Codable { var ref: String }
    struct Label: Codable { var name: String }
    var number: Int
    var title: String
    var html_url: String
    var state: String
    var draft: Bool?
    var user: GitHubPull.User
    var head: Head
    var base: Base?
    var labels: [Label]
    /// False when the pull request conflicts with its base; nil while GitHub works it out.
    var mergeable: Bool?
    /// GitHub's word for it: "dirty" is a conflict ("clean", "blocked", "behind", "unknown"…).
    var mergeable_state: String?
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

/// A job's log that cannot be read from here: no right to, gone, or not an answer to trust.
enum GitHubLogError: Error, Equatable { case unavailable(Int) }

/// Stops at a redirect and hands it back, so its address can be read.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
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
        // The primary limit (no requests left until the reset) and the secondary one (too
        // many at once) both come as 403 or 429, with how long to wait.
        if code == 429 || code == 403, let http {
            let after = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            let reset = http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"
                ? http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Double.init).map { $0 - Date().timeIntervalSince1970 } : nil
            if let wait = after ?? reset { throw AppError.rateLimited(.github, retryAfter: min(max(wait, 1), 3600)) }
            if code == 429 { throw AppError.rateLimited(.github, retryAfter: 60) }
        }
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

    /// The checks of a few pull requests by number, and whether each is still open: what is
    /// read while checks are running, a fraction of a kilobyte per pull request.
    func checks(_ repo: String, numbers: [Int]) async throws -> [Int: (checks: String?, open: Bool)] {
        struct Node: Decodable {
            var number: Int
            var state: String
            var commits: PullNode.Commits?
        }
        struct R: Decodable { var repository: [String: Node?]? }
        let wanted = Array(Set(numbers)).sorted().prefix(30)
        guard !wanted.isEmpty else { return [:] }
        let fields = wanted.map { "p\($0): pullRequest(number: \($0)) { number state commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }" }
        let found = try await graphql("""
        query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { \(fields.joined(separator: " ")) } }
        """, variables: Self.split(repo), as: R.self).repository ?? [:]
        var out: [Int: (checks: String?, open: Bool)] = [:]
        for case let node? in found.values {
            out[node.number] = (node.commits?.nodes.first?.commit.statusCheckRollup?.state, node.state == "OPEN")
        }
        return out
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

    /// When a commit was made (its committer date): the git object alone, under a kilobyte,
    /// and it never changes, so one read per commit is enough.
    func commitDate(_ repo: String, sha: String) async throws -> Date? {
        struct Who: Decodable { var date: String }
        struct R: Decodable { var committer: Who }
        return ISO8601DateFormatter().date(from: try await get("/repos/\(repo)/git/commits/\(sha)", as: R.self).committer.date)
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

    /// The checks of a pull request's head commit that failed, with the step each Actions job
    /// failed on: one GraphQL query, read when someone asks why (about 1 kB for ten checks).
    func failedChecks(_ repo: String, number: Int) async throws -> GitHubFailedChecks {
        struct Context: Decodable {
            struct Suite: Decodable { struct Run: Decodable { var databaseId: Int? }; var workflowRun: Run? }
            struct Steps: Decodable { struct Step: Decodable { var name: String; var conclusion: String? }; var nodes: [Step] }
            // A check run (an Actions job, or another app's check).
            var name: String?, conclusion: String?, status: String?, databaseId: Int?, detailsUrl: String?, completedAt: String?
            var checkSuite: Suite?, steps: Steps?
            // A commit status.
            var context: String?, state: String?, targetUrl: String?, createdAt: String?
        }
        struct R: Decodable {
            struct Repo: Decodable {
                struct Pull: Decodable {
                    struct Commits: Decodable {
                        struct Node: Decodable {
                            struct Commit: Decodable {
                                struct Rollup: Decodable { struct Contexts: Decodable { var nodes: [Context] }; var contexts: Contexts }
                                var oid: String; var statusCheckRollup: Rollup?
                            }
                            var commit: Commit
                        }
                        var nodes: [Node]
                    }
                    var commits: Commits
                }
                var pullRequest: Pull?
            }
            var repository: Repo?
        }
        var variables = Self.split(repo)
        variables["number"] = number
        let r = try await graphql("""
        query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){
          commits(last:1){nodes{commit{oid statusCheckRollup{contexts(first:100){nodes{__typename
            ... on CheckRun{name conclusion status databaseId detailsUrl completedAt checkSuite{workflowRun{databaseId}} steps(first:60){nodes{name conclusion}}}
            ... on StatusContext{context state targetUrl createdAt}}}}}}}}}}
        """, variables: variables, as: R.self)
        guard let commit = r.repository?.pullRequest?.commits.nodes.first?.commit else {
            throw AppError.message("GitHub: pull request #\(number) of \(repo) not found, or this account cannot see it")
        }
        let iso = ISO8601DateFormatter()
        let failed = (commit.statusCheckRollup?.contexts.nodes ?? []).compactMap { c -> GitHubFailedCheck? in
            if let name = c.name {
                guard ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE"].contains(c.conclusion ?? "") else { return nil }
                return GitHubFailedCheck(name: name, url: c.detailsUrl ?? "",
                                         jobID: c.checkSuite?.workflowRun?.databaseId == nil ? nil : c.databaseId,
                                         step: c.steps?.nodes.first { $0.conclusion == "FAILURE" || $0.conclusion == "TIMED_OUT" }?.name,
                                         completedAt: c.completedAt.flatMap(iso.date))
            }
            guard let name = c.context, ["FAILURE", "ERROR"].contains(c.state ?? "") else { return nil }
            return GitHubFailedCheck(name: name, url: c.targetUrl ?? "", jobID: nil, step: nil, completedAt: c.createdAt.flatMap(iso.date))
        }
        let all = commit.statusCheckRollup?.contexts.nodes ?? []
        let passing = all.filter { ["SUCCESS", "NEUTRAL", "SKIPPED"].contains($0.conclusion ?? "") || $0.state == "SUCCESS" }.count
        let running = all.filter { ($0.name != nil && $0.status != "COMPLETED") || ["PENDING", "EXPECTED"].contains($0.state ?? "") }.count
        return GitHubFailedChecks(sha: commit.oid, failed: failed, passing: passing, running: running)
    }

    /// The end of an Actions job's log: `bytes` at most, and whether its start was left out.
    /// GitHub answers with the address of the log in its storage, which is then asked for its
    /// size and for its last bytes only; a log shorter than `bytes` comes whole.
    func jobLogTail(_ repo: String, jobID: Int, bytes: Int) async throws -> (data: Data, cut: Bool) {
        let path = "/repos/\(repo)/actions/jobs/\(jobID)/logs"
        var req = URLRequest(url: URL(string: "https://api.github.com" + path)!, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        var started = Date()
        // The redirect is followed by hand: the token must not travel to the storage host.
        let (_, resp) = try await URLSession.shared.data(for: req, delegate: NoRedirect())
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        RequestLog.record("github", "GET \(path)", status: code, bytes: 0, since: started)
        if code == 401 { throw AppError.unauthorized(.github) }
        if code == 429 || (code == 403 && http?.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0") {
            let wait = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 60
            throw AppError.rateLimited(.github, retryAfter: min(max(wait, 1), 3600))
        }
        // 403: no right to read Actions here. 404: no such job for this account. 410: the log expired.
        guard (300..<400).contains(code), let location = http?.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:)),
              location.scheme == "https" else { throw GitHubLogError.unavailable(code) }

        var head = URLRequest(url: location, cachePolicy: .reloadIgnoringLocalCacheData)
        head.httpMethod = "HEAD"
        let length = ((try? await URLSession.shared.data(for: head))?.1 as? HTTPURLResponse)
            .flatMap { $0.value(forHTTPHeaderField: "Content-Length") }.flatMap(Int.init)
        var get = URLRequest(url: location, cachePolicy: .reloadIgnoringLocalCacheData)
        // Without a size the whole log would come: refuse rather than download megabytes.
        guard let length else { throw GitHubLogError.unavailable(0) }
        let cut = length > bytes
        if cut { get.setValue("bytes=\(length - bytes)-", forHTTPHeaderField: "Range") }
        started = Date()
        let (data, answer) = try await URLSession.shared.data(for: get)
        let status = (answer as? HTTPURLResponse)?.statusCode ?? 0
        RequestLog.record("github", "GET job log (storage)", status: status, bytes: data.count, since: started)
        guard status == 200 || status == 206 else { throw GitHubLogError.unavailable(status) }
        // A storage that ignored the range sent everything: keep the end.
        return (data.count > bytes ? data.suffix(bytes) : data, cut)
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
