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
    /// Who wrote the message, for an item that comes from one.
    var author: String? = nil
    /// The item comes from a long Slack message: where its summary is kept, and what it is
    /// written from (docs/on-device-ai.md, 5.7). Nil for everything else, short messages included.
    var summary: Summary? = nil

    struct Summary: Equatable {
        /// The entry the project's rail writes for the same message: one copy.
        let subject: IntelligenceStore.Subject
        let input: MessageSummary.Input
    }

    /// The most summaries the Overview asks for at once. One is written at a time, so each one
    /// asked for here is one to three seconds the others wait.
    static let mostSummaries = 6
    /// The items listed under a project before "Show all".
    static let listed = 3

    /// The items whose summary the Overview asks for, out of those it shows: the newest first,
    /// `mostSummaries` at most. What is seen first is written first.
    static func toSummarise(_ shown: [WaitingItem]) -> [WaitingItem] {
        Array(shown.filter { $0.summary != nil }.sorted { $0.date > $1.date }.prefix(mostSummaries))
    }

    /// What the item's line shows in place of the cut message once its summary is written: the
    /// kind and the sentence. Nil keeps the excerpt: no summary yet, silence, or not a long message.
    func summarised(by text: GeneratedText?) -> (kind: String?, sentence: String)? {
        guard summary != nil, let text, !text.isEmpty else { return nil }
        return (text.kind, text.sentences.map(\.text).joined(separator: " "))
    }

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
    /// - Parameter channelID: the Slack channel's id, which keys the summaries of its messages.
    func waiting(channel: String?, channelID: String? = nil) -> [WaitingItem] {
        var out: [WaitingItem] = []
        for m in slack?.mentions ?? [] {
            var summary: WaitingItem.Summary?
            if let channelID, let input = m.summary {
                summary = .init(subject: MessageSummary.subject(channel: channelID, ts: m.ts), input: input)
            }
            out.append(.init(kind: .mention, text: "\(m.author): \(m.text)", date: m.date, target: .slack(ts: m.ts),
                             author: m.author, summary: summary))
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
