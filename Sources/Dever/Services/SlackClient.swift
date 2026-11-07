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
    var reply_users: [String]?
    var latest_reply: String?
    var subtype: String?
    var thread_ts: String?
    var files: [SlackFile]?
    var attachments: [SlackAttachment]?
    var blocks: [SlackBlock]?
    var reactions: [SlackReaction]?
    var id: String { ts }
    var date: Date { Date(timeIntervalSince1970: Double(ts) ?? 0) }
    /// A thread parent is its own message; a reply carries its parent's `thread_ts`.
    var isReply: Bool { thread_ts != nil && thread_ts != ts }
}

/// An emoji reaction and who gave it.
struct SlackReaction: Codable, Identifiable, Hashable {
    var name: String
    var count: Int
    var users: [String]?
    var id: String { name }
}

/// A file shared in a message. Thumbnails and `url_private` are served only with the
/// user token as a bearer (scope `files:read`); `permalink` opens the file in Slack.
struct SlackFile: Codable, Identifiable {
    var id: String
    var name: String?
    var title: String?
    var mimetype: String?
    var filetype: String?
    var size: Int?
    var mode: String?
    var file_access: String?
    var is_external: Bool?
    var permalink: String?
    var url_private: String?
    var thumb_360: String?
    var thumb_360_w: Int?
    var thumb_360_h: Int?
    var thumb_480: String?
    var thumb_480_w: Int?
    var thumb_480_h: Int?
    var original_w: Int?
    var original_h: Int?

    /// Slack answers with `file_access` other than "visible" (or a tombstone mode) for files
    /// the token may not read: private ones, or ones hidden by the free plan's limit.
    var isReadable: Bool {
        (file_access ?? "visible") == "visible" && !["tombstone", "hidden_by_limit"].contains(mode ?? "")
    }
    var isImage: Bool { mimetype?.hasPrefix("image/") == true && thumb_360 != nil }
    var displayName: String { title.flatMap { $0.isEmpty ? nil : $0 } ?? name ?? "File" }
}

/// A legacy attachment or a link unfurl: a small card with the site, a title and a line of text.
struct SlackAttachment: Codable, Identifiable {
    var id: Int?
    var fallback: String?
    var title: String?
    var title_link: String?
    var text: String?
    var pretext: String?
    var service_name: String?
    var author_name: String?
    var from_url: String?
    var original_url: String?
    var image_url: String?
    var thumb_url: String?
    var color: String?
    var is_app_unfurl: Bool?
    var is_msg_unfurl: Bool?
    var channel_id: String?
    var channel_name: String?
    var author_subname: String?
    var footer: String?
    var ts: FlexibleString?
    var isEmpty: Bool { title == nil && text == nil && pretext == nil && image_url == nil && fallback == nil }
    /// A Slack message quoted in this one (shared or unfurled).
    var isMessageUnfurl: Bool {
        is_msg_unfurl == true || (from_url ?? "").range(of: #"slack\.com/archives/[A-Z0-9]+/p\d+"#, options: .regularExpression) != nil
    }
}

/// A value Slack sends as a string in one place and a number in another (attachment `ts`).
struct FlexibleString: Codable, Hashable {
    var value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let d = try? c.decode(Double.self) { value = String(d) }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else { throw DecodingError.typeMismatch(String.self, .init(codingPath: decoder.codingPath, debugDescription: "string or number")) }
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value) }
}

/// Block Kit, as far as reading goes: `rich_text` blocks with their nested elements.
/// Other block types are carried by `type` only; their content is covered by `text`.
struct SlackBlock: Codable {
    var type: String
    var elements: [SlackRichElement]?
}

/// One node of a rich text tree: a section, list, quote or preformatted block, or a leaf
/// (text, link, user, channel, emoji, broadcast). Leaves carry a `style`.
struct SlackRichElement: Codable {
    struct Style: Codable {
        var bold: Bool?
        var italic: Bool?
        var strike: Bool?
        var code: Bool?
    }
    var type: String
    var text: String?
    var url: String?
    var user_id: String?
    var channel_id: String?
    var name: String?
    var unicode: String?
    var range: String?
    var style: Style?
    var elements: [SlackRichElement]?
    var indent: Int?
    var border: Int?
    // `style` is a string ("bullet"/"ordered") on lists and an object on leaves.
    var listStyle: String?

    private enum CodingKeys: String, CodingKey {
        case type, text, url, user_id, channel_id, name, unicode, range, style, elements, indent, border
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        user_id = try c.decodeIfPresent(String.self, forKey: .user_id)
        channel_id = try c.decodeIfPresent(String.self, forKey: .channel_id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        unicode = try c.decodeIfPresent(String.self, forKey: .unicode)
        range = try c.decodeIfPresent(String.self, forKey: .range)
        elements = try c.decodeIfPresent([SlackRichElement].self, forKey: .elements)
        indent = try c.decodeIfPresent(Int.self, forKey: .indent)
        border = try c.decodeIfPresent(Int.self, forKey: .border)
        style = try? c.decodeIfPresent(Style.self, forKey: .style)
        listStyle = try? c.decodeIfPresent(String.self, forKey: .style)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(user_id, forKey: .user_id)
        try c.encodeIfPresent(channel_id, forKey: .channel_id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(unicode, forKey: .unicode)
        try c.encodeIfPresent(elements, forKey: .elements)
        try c.encodeIfPresent(indent, forKey: .indent)
        if let style { try c.encode(style, forKey: .style) } else if let listStyle { try c.encode(listStyle, forKey: .style) }
    }
}

/// A workspace member as the thread needs it: a name to show and a 72px avatar.
struct SlackUser: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var avatar: URL?
    var isBot: Bool
}

/// One page of channel history, newest first.
struct SlackHistoryPage {
    var messages: [SlackMessage]
    var hasMore: Bool
}

/// Slack: OAuth v2 with user scopes. Slack requires an HTTPS redirect, so it points
/// to a static page (GitHub Pages, see docs/oauth) that forwards the code to
/// http://localhost:47321/slack/callback.
enum SlackAuth {
    static let callbackPath = "/slack/callback"
    static let userScopes = [
        "channels:read", "groups:read", "channels:history", "groups:history",
        "channels:write", "groups:write", "users:read", "team:read", "files:read",
        "chat:write", "reactions:read", "reactions:write", "emoji:read",
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

    /// One member by id (`users.info`): the signed-in user, for Settings.
    func user(_ id: String) async throws -> SlackUser {
        let m = try await call("users.info", ["user": id])["user"] as? [String: Any] ?? [:]
        let profile = m["profile"] as? [String: Any]
        let display = (profile?["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let name = (m["real_name"] as? String) ?? display ?? (m["name"] as? String) ?? id
        let image = (profile?["image_72"] as? String) ?? (profile?["image_48"] as? String)
        return SlackUser(id: id, name: name, avatar: image.flatMap(URL.init(string:)), isBot: m["is_bot"] as? Bool ?? false)
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

    /// The channel's messages before `before` (a message `ts`), or the latest ones when nil.
    /// Pages of 20 keep each request small; `hasMore` says whether an earlier page exists.
    func historyPage(_ channelID: String, before: String? = nil, limit: Int = 20) async throws -> SlackHistoryPage {
        var params = ["channel": channelID, "limit": "\(limit)"]
        if let before { params["latest"] = before; params["inclusive"] = "false" }
        let res = try await call("conversations.history", params)
        return SlackHistoryPage(messages: try decode(res["messages"], as: [SlackMessage].self),
                                hasMore: res["has_more"] as? Bool ?? false)
    }

    /// A thread's replies, oldest first, without the parent message.
    func replies(_ channelID: String, threadTS: String, limit: Int = 100) async throws -> [SlackMessage] {
        let res = try await call("conversations.replies", ["channel": channelID, "ts": threadTS, "limit": "\(limit)"])
        return try decode(res["messages"], as: [SlackMessage].self).filter { $0.ts != threadTS }
    }

    /// The workspace's custom emoji: name → image URL, aliases resolved.
    func customEmoji() async throws -> [String: URL] {
        let res = try await call("emoji.list")
        let raw = res["emoji"] as? [String: String] ?? [:]
        var out: [String: URL] = [:]
        for (name, value) in raw where !value.hasPrefix("alias:") { out[name] = URL(string: value) }
        for (name, value) in raw where value.hasPrefix("alias:") {
            if let target = out[String(value.dropFirst(6))] { out[name] = target }
        }
        return out
    }

    /// Posts `text` as a reply in the thread of `threadTS`, as the signed-in user.
    func reply(_ channelID: String, threadTS: String, text: String) async throws {
        _ = try await call("chat.postMessage", ["channel": channelID, "thread_ts": threadTS, "text": text])
    }

    /// Adds or removes the signed-in user's reaction `name` ("+1", "heart") on a message.
    func react(_ channelID: String, ts: String, name: String, on: Bool) async throws {
        do {
            _ = try await call(on ? "reactions.add" : "reactions.remove", ["channel": channelID, "timestamp": ts, "name": name])
        } catch AppError.message(let m) where m.hasSuffix("already_reacted") || m.hasSuffix("no_reaction") {
            // Already in the wanted state.
        }
    }

    /// Bytes of a Slack-hosted file or thumbnail (`url_private`, `thumb_*`). Slack serves them
    /// only with the token as a bearer and answers a login page otherwise, hence the type check.
    func download(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard http?.statusCode == 200, !type.contains("text/html") else {
            throw AppError.message("Slack file: not available (\(http?.statusCode ?? 0))")
        }
        return data
    }

    func createChannel(name: String, isPrivate: Bool) async throws -> SlackChannel {
        let res = try await call("conversations.create", ["name": name, "is_private": isPrivate ? "true" : "false"])
        return try decode(res["channel"], as: SlackChannel.self)
    }

    func userNames() async throws -> [String: String] {
        try await users().mapValues(\.name)
    }

    /// Every member of the workspace in one `users.list` (paged by 1000), with the 72px
    /// avatar: the size Slack's own clients use for message rows at 2x.
    func users() async throws -> [String: SlackUser] {
        var out: [String: SlackUser] = [:]
        var cursor = ""
        repeat {
            let res = try await call("users.list", ["limit": "1000", "cursor": cursor])
            for m in res["members"] as? [[String: Any]] ?? [] {
                guard let id = m["id"] as? String else { continue }
                let profile = m["profile"] as? [String: Any]
                let display = (profile?["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let name = display ?? (m["real_name"] as? String) ?? (m["name"] as? String) ?? id
                let image = (profile?["image_72"] as? String) ?? (profile?["image_48"] as? String)
                out[id] = SlackUser(id: id, name: name, avatar: image.flatMap(URL.init(string:)),
                                    isBot: m["is_bot"] as? Bool ?? false)
            }
            cursor = (res["response_metadata"] as? [String: Any])?["next_cursor"] as? String ?? ""
        } while !cursor.isEmpty
        return out
    }
}
