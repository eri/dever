import Foundation

/// Slack user token (`xoxp-…`) obtained through the "Dever" OAuth app installed
/// in the workspace. With token rotation disabled, it never expires.
struct SlackCredentials: Codable {
    var teamID: String
    var teamName: String
    var domain: String
    var userID: String
    var token: String
}

struct SlackChannel: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var is_private: Bool?
    var is_member: Bool?
    var num_members: Int?
}

struct SlackMessage: Codable, Identifiable {
    var ts: String
    var user: String?
    var text: String?
    var reply_count: Int?
    var subtype: String?
    var id: String { ts }
    var date: Date { Date(timeIntervalSince1970: Double(ts) ?? 0) }
}

/// Slack: OAuth v2 with user scopes. Slack requires an HTTPS redirect, so it points
/// to a static page (GitHub Pages, see docs/oauth) that forwards the code to
/// http://localhost:47321/slack/callback.
enum SlackAuth {
    static let callbackPath = "/slack/callback"
    static let userScopes = [
        "channels:read", "groups:read", "channels:history", "groups:history",
        "channels:write", "groups:write", "users:read", "team:read",
    ].joined(separator: ",")

    static func connect() async throws -> SlackCredentials {
        guard let cfg = DeverConfig.shared.slack else {
            throw AppError.message("Slack OAuth app not configured (dever.json) — see docs/SETUP.md")
        }
        let state = OAuth.randomString()
        var c = URLComponents(string: "https://slack.com/oauth/v2/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: cfg.clientID),
            .init(name: "user_scope", value: userScopes),
            .init(name: "redirect_uri", value: cfg.redirectURL),
            .init(name: "state", value: state),
        ]
        let code = try await OAuth.authorize(c.url!, callbackPath: callbackPath, state: state)

        var req = URLRequest(url: URL(string: "https://slack.com/api/oauth.v2.access")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = OAuth.form([
            "client_id": cfg.clientID,
            "client_secret": cfg.clientSecret,
            "code": code,
            "redirect_uri": cfg.redirectURL,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard obj["ok"] as? Bool == true,
              let user = obj["authed_user"] as? [String: Any],
              let token = user["access_token"] as? String,
              let team = obj["team"] as? [String: Any] else {
            throw AppError.message("Slack OAuth: \(obj["error"] as? String ?? "invalid response")")
        }
        var creds = SlackCredentials(teamID: team["id"] as? String ?? "", teamName: team["name"] as? String ?? "",
                                     domain: "", userID: user["id"] as? String ?? "", token: token)
        let info = try await SlackClient(creds: creds).call("team.info")
        creds.domain = (info["team"] as? [String: Any])?["domain"] as? String ?? ""
        return creds
    }
}

struct SlackClient {
    var creds: SlackCredentials

    func call(_ method: String, _ params: [String: String] = [:]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = OAuth.form(params)
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if obj["ok"] as? Bool == true { return obj }
        let err = obj["error"] as? String ?? "unknown_error"
        if ["invalid_auth", "not_authed", "token_revoked", "token_expired"].contains(err) {
            throw AppError.unauthorized(.slack)
        }
        throw AppError.message("Slack \(method): \(err)")
    }

    private func decode<T: Decodable>(_ value: Any?, as: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: value ?? [])
        return try JSONDecoder().decode(T.self, from: data)
    }

    func authTest() async throws -> String {
        try await call("auth.test")["user"] as? String ?? "?"
    }

    func channels() async throws -> [SlackChannel] {
        var all: [SlackChannel] = []
        var cursor = ""
        repeat {
            let res = try await call("conversations.list", [
                "types": "public_channel,private_channel",
                "exclude_archived": "true",
                "limit": "1000",
                "cursor": cursor,
            ])
            all += try decode(res["channels"], as: [SlackChannel].self)
            cursor = (res["response_metadata"] as? [String: Any])?["next_cursor"] as? String ?? ""
        } while !cursor.isEmpty
        return all.sorted { $0.name < $1.name }
    }

    func history(_ channelID: String, limit: Int = 30, since: Date? = nil) async throws -> [SlackMessage] {
        var params = ["channel": channelID, "limit": "\(limit)"]
        if let since { params["oldest"] = String(since.timeIntervalSince1970) }
        let res = try await call("conversations.history", params)
        return try decode(res["messages"], as: [SlackMessage].self)
    }

    func createChannel(name: String, isPrivate: Bool) async throws -> SlackChannel {
        let res = try await call("conversations.create", ["name": name, "is_private": isPrivate ? "true" : "false"])
        return try decode(res["channel"], as: SlackChannel.self)
    }

    func userNames() async throws -> [String: String] {
        let res = try await call("users.list", ["limit": "1000"])
        let members = res["members"] as? [[String: Any]] ?? []
        var out: [String: String] = [:]
        for m in members {
            guard let id = m["id"] as? String else { continue }
            let profile = m["profile"] as? [String: Any]
            let display = (profile?["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            out[id] = display ?? (m["real_name"] as? String) ?? (m["name"] as? String) ?? id
        }
        return out
    }
}
