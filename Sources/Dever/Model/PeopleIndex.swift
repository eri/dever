import Foundation
import SwiftUI

/// Who is who across Linear and Slack, by work email: the only key both tools share that two
/// people never have in common (names collide and drift). People keep their Slack picture up to
/// date, rarely their Linear one, so a Linear avatar shows the Slack photo when the emails match,
/// and Linear's own picture otherwise.
///
/// Data contract: reads Linear `users { id email }` (one query, 1 h, `IssueStore.people`) and the
/// emails that Slack's `users.list` already returns (`SlackDirectory`, 15 min, scope
/// `users:read.email`). No request of its own. Writes nothing. Memory only.
enum PeopleMatch {
    static func key(_ email: String?) -> String? {
        guard let e = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), e.contains("@") else { return nil }
        return e
    }

    /// Slack pictures by email, people with no picture or no email left out; bots never match.
    static func slackPhotos(_ users: some Sequence<SlackUser>) -> [String: URL] {
        var out: [String: URL] = [:]
        for u in users where !u.isBot {
            if let k = key(u.email), let avatar = u.avatar { out[k] = avatar }
        }
        return out
    }

    /// The Slack picture of a Linear user, or nil when either side does not know them.
    static func photo(linearID: String?, linearEmails: [String: String], slackPhotos: [String: URL]) -> URL? {
        guard let id = linearID, let k = key(linearEmails[id]) else { return nil }
        return slackPhotos[k]
    }
}

@MainActor
final class PeopleIndex: ObservableObject {
    static let shared = PeopleIndex()

    @Published private(set) var slackPhotos: [String: URL] = [:]
    @Published private(set) var linearEmails: [String: String] = [:]

    func slack(_ users: some Sequence<SlackUser>) {
        let photos = PeopleMatch.slackPhotos(users)
        if photos != slackPhotos { slackPhotos = photos }
    }

    func linear(_ emails: [String: String]) {
        if emails != linearEmails { linearEmails = emails }
    }

    func photo(linearID: String?) -> URL? {
        PeopleMatch.photo(linearID: linearID, linearEmails: linearEmails, slackPhotos: slackPhotos)
    }
}
