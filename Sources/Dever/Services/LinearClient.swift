import Foundation

struct LinearAccount: Codable {
    var userName: String
    var email: String
    var orgName: String
    var urlKey: String
}

/// Linear OAuth token: valid for 24 h, renewed automatically with the refresh token.
struct LinearCredentials: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var account: LinearAccount

    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 300 }
}

struct LinearTeam: Codable, Identifiable, Hashable {
    var id: String
    var key: String
    var name: String
}

struct LinearProject: Codable, Identifiable, Hashable {
    struct Teams: Codable, Hashable { var nodes: [LinearTeam] }
    var id: String
    var name: String
    var url: String
    var teams: Teams?
}

struct LinearIssue: Codable, Identifiable {
    struct State: Codable { var name: String; var type: String }
    struct Person: Codable { var name: String }
    var id: String
    var identifier: String
    var title: String
    var url: String
    var updatedAt: String
    var state: State
    var assignee: Person?
    var branchName: String?
    var attachments: Attachments?
}

/// Links attached to a Linear issue (GitHub PRs, among others).
struct Attachments: Codable, Hashable {
    struct Node: Codable, Hashable { var url: String }
    var nodes: [Node]
}

/// What ties a pull request to a Linear issue: its identifier, its suggested
/// branch name and the PR links Linear's GitHub integration attached to it.
protocol IssueReference {
    var identifier: String { get }
    var branchName: String? { get }
    var attachments: Attachments? { get }
}

extension LinearIssue: IssueReference {}

/// Linear: OAuth 2 with PKCE (no embedded secret) through the workspace's "Dever"
/// OAuth app. The browser handles sign-in; the app receives the code on
/// http://localhost:47321/linear/callback.
enum LinearAuth {
    static let callbackPath = "/linear/callback"
    static var redirectURI: String { OAuth.loopbackURL(callbackPath) }
    static let scopes = "read,write"

    struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Double?
    }

    static func connect() async throws -> LinearCredentials {
        guard let clientID = DeverConfig.shared.linear?.clientID else {
            throw AppError.message("Linear OAuth app not configured (dever.json) — see docs/SETUP.md")
        }
        let verifier = OAuth.randomString(48)
        let state = OAuth.randomString()
        var c = URLComponents(string: "https://linear.app/oauth/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: OAuth.pkceChallenge(verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "consent"),
        ]
        let code = try await OAuth.authorize(c.url!, callbackPath: callbackPath, state: state)
        let token = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        let account = try await LinearClient(token: token.access_token).viewer()
        return credentials(token, account: account, previousRefresh: nil)
    }

    static func refresh(_ creds: LinearCredentials) async throws -> LinearCredentials {
        guard let clientID = DeverConfig.shared.linear?.clientID, let refresh = creds.refreshToken else {
            throw AppError.unauthorized(.linear)
        }
        let token = try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ])
        return credentials(token, account: creds.account, previousRefresh: refresh)
    }

    private static func credentials(_ t: TokenResponse, account: LinearAccount, previousRefresh: String?) -> LinearCredentials {
        LinearCredentials(accessToken: t.access_token,
                          refreshToken: t.refresh_token ?? previousRefresh,
                          expiresAt: Date().addingTimeInterval(t.expires_in ?? 86_400),
                          account: account)
    }

    private static func tokenRequest(_ params: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://api.linear.app/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = OAuth.form(params)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 400 || code == 401 { throw AppError.unauthorized(.linear) }
        guard (200..<300).contains(code) else {
            throw AppError.message("Linear OAuth \(code): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

/// GraphQL client for Linear's public API.
struct LinearClient {
    var token: String

    func query<T: Decodable>(_ query: String, variables: [String: Any] = [:], as: T.Type = T.self) async throws -> T {
        var req = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            let isAuth = errors.contains {
                (($0["extensions"] as? [String: Any])?["code"] as? String) == "AUTHENTICATION_ERROR"
            }
            if isAuth || status == 401 { throw AppError.unauthorized(.linear) }
            let msg = errors.compactMap { $0["message"] as? String }.joined(separator: " · ")
            throw AppError.message("Linear: \(msg)")
        }
        if status == 401 { throw AppError.unauthorized(.linear) }
        guard let dataObj = json["data"] else {
            throw AppError.message("Linear \(status): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: dataObj))
    }

    func viewer() async throws -> LinearAccount {
        struct R: Decodable {
            struct V: Decodable {
                struct O: Decodable { var name: String; var urlKey: String }
                var name: String; var email: String; var organization: O
            }
            var viewer: V
        }
        let v = try await query("{ viewer { name email organization { name urlKey } } }", as: R.self).viewer
        return LinearAccount(userName: v.name, email: v.email, orgName: v.organization.name, urlKey: v.organization.urlKey)
    }

    func teams() async throws -> [LinearTeam] {
        struct R: Decodable { struct C: Decodable { var nodes: [LinearTeam] }; var teams: C }
        return try await query("{ teams(first: 100) { nodes { id key name } } }", as: R.self).teams.nodes
    }

    func projects() async throws -> [LinearProject] {
        struct R: Decodable {
            struct C: Decodable {
                struct P: Decodable { var hasNextPage: Bool; var endCursor: String? }
                var nodes: [LinearProject]; var pageInfo: P
            }
            var projects: C
        }
        var all: [LinearProject] = []
        var after: Any = NSNull()
        for _ in 0..<10 {
            let r = try await query("""
            query($after: String) { projects(first: 100, after: $after) {
              nodes { id name url teams { nodes { id key name } } }
              pageInfo { hasNextPage endCursor } } }
            """, variables: ["after": after], as: R.self).projects
            all += r.nodes
            guard r.pageInfo.hasNextPage, let c = r.pageInfo.endCursor else { break }
            after = c
        }
        return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func issues(projectID: String) async throws -> [LinearIssue] {
        struct R: Decodable {
            struct P: Decodable { struct C: Decodable { var nodes: [LinearIssue] }; var issues: C }
            var project: P
        }
        return try await query("""
        query($id: String!) { project(id: $id) { issues(first: 250, orderBy: updatedAt) { nodes {
          id identifier title url updatedAt state { name type } assignee { name }
          branchName attachments { nodes { url } } } } } }
        """, variables: ["id": projectID], as: R.self).project.issues.nodes
    }

    struct ProjectSummary: Decodable {
        struct Person: Decodable { var name: String }
        struct Issue: Decodable, IssueReference {
            struct State: Decodable { var type: String }
            var state: State
            var identifier: String
            var branchName: String?
            var attachments: Attachments?
        }
        struct Issues: Decodable { var nodes: [Issue] }
        var targetDate: String?
        var lead: Person?
        var issues: Issues
    }

    /// Lightweight project data for the overview: lead, target date, issue states and PR links.
    func projectSummary(id: String) async throws -> ProjectSummary {
        struct R: Decodable { var project: ProjectSummary }
        return try await query("""
        query($id: String!) { project(id: $id) { targetDate lead { name }
          issues(first: 250) { nodes { state { type } identifier branchName attachments { nodes { url } } } } } }
        """, variables: ["id": id], as: R.self).project
    }

    func createProject(name: String, teamIDs: [String]) async throws -> LinearProject {
        struct R: Decodable { struct C: Decodable { var project: LinearProject }; var projectCreate: C }
        return try await query("""
        mutation($input: ProjectCreateInput!) { projectCreate(input: $input) {
          project { id name url teams { nodes { id key name } } } } }
        """, variables: ["input": ["name": name, "teamIds": teamIDs]], as: R.self).projectCreate.project
    }
}
