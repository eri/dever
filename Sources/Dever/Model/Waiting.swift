import Foundation

/// What waits for you in one project, as the Overview lists it under the project: pull requests
/// whose review is asked of you, Slack messages that name you, and the rest of what arrived in
/// the channel since you last read it. Each item knows where it opens inside Dever.
struct WaitingItem: Identifiable, Equatable {
    enum Kind: Equatable { case mention, review, unread }

    let kind: Kind
    let text: String
    let date: Date
    let target: ProjectFocus.Target

    var id: String {
        switch target {
        case .slack(let ts): "\(kind)-\(ts)"
        case .pull(_, let url): "\(kind)-\(url)"
        }
    }

    var symbol: String {
        switch kind {
        case .mention: "at"
        case .review: "arrow.triangle.pull"
        case .unread: "bubble.left"
        }
    }
}

extension ProjectSnapshot {
    /// Mentions first (someone is asking you), then review requests, then one line for the
    /// rest of the unread messages; newest first within each kind.
    func waiting(channel: String?) -> [WaitingItem] {
        var out: [WaitingItem] = []
        for m in slack?.mentions ?? [] {
            out.append(.init(kind: .mention, text: "\(m.author): \(m.text)", date: m.date, target: .slack(ts: m.ts)))
        }
        for r in github?.reviewRequests ?? [] {
            out.append(.init(kind: .review, text: "Review #\(r.number) \(r.title)", date: r.date,
                             target: .pull(issue: r.issue, url: r.url)))
        }
        if let s = slack, let unread = s.unread, unread > s.mentions.count, let first = s.firstUnreadTS {
            let rest = unread - s.mentions.count
            let count = s.unreadCapped ? "\(rest)+" : "\(rest)"
            let place = channel.map { " in #\($0)" } ?? ""
            out.append(.init(kind: .unread, text: s.mentions.isEmpty ? "\(count) unread\(place)" : "\(count) more unread\(place)",
                             date: s.lastUnreadAt ?? Date(), target: .slack(ts: first)))
        }
        return out
    }

    /// The latest thing that happened: a message in the channel or a merge, whichever is newer.
    func lastActivity(channel: String?) -> (text: String, date: Date)? {
        var best: (text: String, date: Date)?
        if let s = slack, let date = s.lastActivity {
            let place = channel.map { " in #\($0)" } ?? ""
            best = ((s.lastAuthor.map { "\($0) wrote" } ?? "Last message") + place, date)
        }
        if let m = github?.lastMerged, m.date > (best?.date ?? .distantPast) {
            best = ("\(m.author) merged #\(m.number)", m.date)
        }
        return best
    }
}

/// Where a click on the Overview should land inside a project's page. The Overview leaves the
/// target here and opens the project; the page takes it once its data has loaded.
@MainActor
enum ProjectFocus {
    enum Target: Equatable {
        /// A Slack message: the reading room opens on it.
        case slack(ts: String)
        /// A pull request: the page of the Linear issue it belongs to, or the project page
        /// itself when it belongs to none.
        case pull(issue: String?, url: String)
    }

    private static var pending: [UUID: Target] = [:]

    static func set(_ target: Target, for project: UUID) { pending[project] = target }

    /// The target left for this project, once.
    static func take(for project: UUID) -> Target? { pending.removeValue(forKey: project) }
}

/// Slack markup as one plain line: mentions as names, links as their label, entities decoded.
enum SlackPlain {
    static func text(_ raw: String, users: [String: SlackUser]) -> String {
        var s = raw
        // <@U123> and <@U123|name>
        s = s.replacingOccurrences(of: #"<@([A-Z0-9]+)(\|[^>]*)?>"#, with: "@$1", options: .regularExpression)
        for (id, user) in users where s.contains("@\(id)") { s = s.replacingOccurrences(of: "@\(id)", with: "@\(user.name)") }
        // <#C123|channel>, <url|label>, <url>
        s = s.replacingOccurrences(of: #"<#[A-Z0-9]+\|([^>]*)>"#, with: "#$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>|]+\|([^>]*)>"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<([^>]*)>"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        return s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
