import Foundation
import os

// The Slack catch-up (docs/on-device-ai.md, 5.1): above the unread messages of the rail, what is
// asked of the reader and the open matters the rail does not show. Nothing here is written by the model: the list is put together from the
// summaries of the messages (5.7), which the model writes well one at a time. Asked to sum up a
// whole channel it was vague or wrong, however it was asked.

enum CatchUp {
    /// Why something was or was not written: counts and reasons only, never a message's words.
    static let log = Logger(subsystem: "io.github.eri.dever", category: "intelligence")

    /// Unread messages from which a catch-up is shown. Below it, reading them is faster.
    static let threshold = 6
    /// Lines shown at most; the rest is a count.
    static let longest = 3

    /// What the store holds for a message's summary.
    enum Summary: Equatable {
        /// None asked for, or none could be written.
        case none
        case pending
        case ready(GeneratedText)
    }

    struct Item: Equatable, Identifiable {
        /// The message it stands for: a click opens the room on it.
        let ts: String
        let kind: String
        let text: String
        /// A request or a question in a message that names the reader, with an @ or without.
        let forYou: Bool
        var id: String { ts }
    }

    struct Digest: Equatable {
        /// What is open, the reader's first, then the newest first.
        var items: [Item]
        /// Unread messages not listed: updates, and what did not fit.
        var more: Int
        /// Summaries still being written: the list may grow.
        var pending: Int
        /// Unread messages older than what is loaded exist: the list says what it covers.
        var covers: Int?
        /// Nothing to point at: no block, rather than one that says so.
        var isEmpty: Bool { items.isEmpty }
    }

    /// The catch-up of a channel, or nil when there is none to show: no read cursor, or fewer
    /// unread messages than the threshold. `messages` is newest first. `firstUnread` is the oldest
    /// unread message the Overview counted, when it knows: with it, a page whose every loaded
    /// message is unread can still tell that nothing older is.
    /// `shown` are the messages the rail displays under the block, each with its own summary: an
    /// open matter among them is listed only when it is for the reader, the list would otherwise
    /// say twice what is on screen.
    static func digest(messages: [SlackMessage], lastRead: String?, hasEarlier: Bool, firstUnread: String? = nil,
                       shown: Set<String> = [],
                       users: [String: SlackUser], me: String?, summary: (SlackMessage) -> Summary) -> Digest? {
        guard let lastRead, let oldest = messages.last else { return nil }
        let unread = messages.filter { !SlackTS.isAtOrBefore($0.ts, lastRead) && !$0.isSystem && !($0.text ?? "").isEmpty }
        guard unread.count >= threshold else { return nil }
        let reachesTheCursor = SlackTS.isAtOrBefore(oldest.ts, lastRead)
            || (firstUnread.map { SlackTS.isAtOrBefore(oldest.ts, $0) } ?? false)
        let reader = me.flatMap { users[$0]?.name } ?? ""

        var pending = 0
        var open: [Item] = []
        for message in unread {
            switch summary(message) {
            case .pending: pending += 1
            case .none: break
            case .ready(let written):
                guard let kind = written.kind, MessageSummary.pressing.contains(kind) else { continue }
                let named = (me.map { (message.text ?? "").contains("<@\($0)") } ?? false)
                    || names(SlackPlain.text(message.text ?? "", users: users), reader: reader)
                open.append(Item(ts: message.ts, kind: kind, text: written.sentences.map(\.text).joined(separator: " "),
                                 forYou: named && kind != "Problem"))
            }
        }
        // The reader's first, then the others, each group newest first (as `unread` is).
        let items = Array((open.filter(\.forYou) + open.filter { !$0.forYou && !shown.contains($0.ts) }).prefix(longest))
        return Digest(items: items, more: unread.count - items.count - pending, pending: pending,
                      covers: hasEarlier && !reachesTheCursor ? unread.count : nil)
    }

    /// `text` holds a word of the reader's name ("Sam" for "Sam Rivers"), as a whole word, whatever
    /// the case and the accents. Words of one or two letters do not count.
    static func names(_ text: String, reader: String) -> Bool {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 })
        }
        return !words(text).isDisjoint(with: words(reader))
    }

    /// What the block says under its lines when it does not cover every unread message.
    static func coverage(_ count: Int) -> String { "Covers the last \(count) unread messages" }

    /// A made-up catch-up for captures.
    static let sample = Digest(items: [
        .init(ts: "3", kind: "Request", text: "Kyryl asks Sam to fix SUP-931 before the release.", forYou: true),
        .init(ts: "2", kind: "Problem", text: "Tip changes take 1 to 2 minutes to sync in the web extension.", forYou: false),
        .init(ts: "1", kind: "Request", text: "Estelle asks for 2 or 3 screenshots of the AI Tips feature.", forYou: false),
    ], more: 9, pending: 2, covers: nil)
}
