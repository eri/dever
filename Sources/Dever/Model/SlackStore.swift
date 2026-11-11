import Foundation

/// What Dever knows of each Slack channel, kept for the session: its messages, Slack's read
/// cursor and the threads that were opened. A project page reads it, so coming back to a
/// project shows its conversation at once, and a reply or a reaction changes one message
/// instead of reading the channel again (docs/data-freshness.md, section 3.1).
@MainActor
final class SlackStore: ObservableObject {
    static let shared = SlackStore()

    struct Channel {
        /// Newest first, as the API returns them; earlier pages are added at the end.
        var messages: [SlackMessage] = []
        /// An earlier page exists beyond the oldest message held.
        var hasEarlier = false
        /// Slack's read cursor: the `ts` of the last message read, in Slack or here.
        var lastRead: String?
        /// The newest message that has been on screen in the room, on its way to the cursor.
        var seenUpTo: String?
        /// The last successful read of the channel's latest page.
        var fetchedAt: Date?
        /// Replies of the threads that were opened, oldest first, by their parent's `ts`.
        var threads: [String: [SlackMessage]] = [:]

        /// New messages replace the ones with the same `ts`; the rest stays as loaded, so a
        /// refresh never throws away earlier pages or re-renders unchanged rows.
        mutating func merge(_ incoming: [SlackMessage]) {
            var byTS = Dictionary(messages.map { ($0.ts, $0) }, uniquingKeysWith: { _, new in new })
            for m in incoming where m.subtype != "channel_join" && m.subtype != "channel_leave" { byTS[m.ts] = m }
            messages = byTS.values.sorted { $0.ts > $1.ts }
        }

        /// The channel's latest page. It says whether earlier messages exist only while it is
        /// all that is held: once earlier pages are in, they are the ones that know.
        mutating func takeLatest(_ page: SlackHistoryPage, limit: Int = 20) {
            merge(page.messages)
            if messages.count <= limit { hasEarlier = page.hasMore }
        }

        mutating func takeEarlier(_ page: SlackHistoryPage) {
            merge(page.messages)
            hasEarlier = page.hasMore
        }

        /// Slack's cursor as just read. Whatever was seen here since keeps precedence over a
        /// cursor that has not caught up yet.
        mutating func cursor(fromSlack cursor: String) {
            lastRead = seenUpTo.map { SlackTS.later($0, cursor) } ?? cursor
        }

        /// A message was on screen. True when it is newer than anything seen before.
        mutating func seen(_ ts: String) -> Bool {
            let next = SlackTS.later(seenUpTo, ts)
            guard next != seenUpTo else { return false }
            seenUpTo = next
            return true
        }

        /// The `ts` to move Slack's cursor to: the newest seen message, when it is past the cursor.
        var cursorToPush: String? {
            guard let seen = seenUpTo, lastRead.map({ !SlackTS.isAtOrBefore(seen, $0) }) ?? true else { return nil }
            return seen
        }

        /// Where "Mark as read" puts the cursor: past the latest message and past the newest
        /// reply of every thread (threads with fresh replies are unread too).
        var readAllTarget: String? {
            guard var target = messages.first?.ts else { return nil }
            for m in messages { if let last = m.latest_reply { target = SlackTS.later(target, last) } }
            return target
        }

        /// A thread as Slack just returned it. Its parent keeps its place in the channel and
        /// takes the counts that changed (a reply was added, here or elsewhere).
        mutating func takeThread(_ parentTS: String, parent: SlackMessage?, replies: [SlackMessage]) {
            threads[parentTS] = replies
            guard let parent, let i = messages.firstIndex(where: { $0.ts == parentTS }) else { return }
            messages[i].reply_count = parent.reply_count
            messages[i].reply_users = parent.reply_users
            messages[i].latest_reply = parent.latest_reply
            if parent.reactions != nil { messages[i].reactions = parent.reactions }
        }

        /// The viewer's reaction on one message, in the channel or in an opened thread.
        mutating func react(_ ts: String, name: String, on: Bool, user: String?) {
            if let i = messages.firstIndex(where: { $0.ts == ts }) {
                messages[i].reactions = SlackReaction.toggled(messages[i].reactions, name: name, on: on, user: user)
            }
            for (parent, replies) in threads {
                guard let j = replies.firstIndex(where: { $0.ts == ts }) else { continue }
                threads[parent]?[j].reactions = SlackReaction.toggled(replies[j].reactions, name: name, on: on, user: user)
            }
        }
    }

    @Published private(set) var channels: [String: Channel] = [:]
    /// The workspace's members and custom emoji, and the names of channels linked from
    /// messages: held here so a page shows names at once (`SlackDirectory` reads them).
    @Published private(set) var users: [String: SlackUser] = [:]
    @Published private(set) var customEmoji: [String: URL] = [:]
    @Published private(set) var channelNames: [String: String] = [:]
    private var loads: [String: Task<Void, Error>] = [:]

    // MARK: Reading

    /// Reads the channel's latest page, its read cursor and what its messages need to be
    /// shown (members, emoji, linked channels). Readers asking at the same moment share it.
    func load(_ id: String, app: AppState) async throws {
        if let running = loads[id] { return try await running.value }
        let task = Task { try await self.fetch(id, app: app) }
        loads[id] = task
        defer { loads[id] = nil }
        try await task.value
    }

    private func fetch(_ id: String, app: AppState) async throws {
        let page = try await app.withSlack { try await $0.historyPage(id, limit: 20) }
        channels[id, default: Channel()].takeLatest(page)
        channels[id]?.fetchedAt = Date()
        let linked = Set(page.messages.flatMap { $0.linkedChannelIDs }).subtracting([id])
        if !linked.isSubset(of: Set(channelNames.keys)),
           let names = try? await app.withSlack({ await SlackDirectory.shared.channelNames(linked, via: $0) }) {
            channelNames.merge(names) { _, new in new }
        }
        if let cursor = try? await app.withSlack({ try await $0.lastRead(id) }) {
            channels[id]?.cursor(fromSlack: cursor)
        }
        if let team = app.slack?.teamID {
            // One users.list per quarter hour across the app, not one per visit.
            let found = try await app.withSlack { try await SlackDirectory.shared.users(team: team, via: $0) }
            if found != users { users = found }
            if customEmoji.isEmpty {
                customEmoji = (try? await app.withSlack { await SlackDirectory.shared.customEmoji(team: team, via: $0) }) ?? [:]
            }
        }
    }

    /// Reads the page before the oldest message held.
    func loadEarlier(_ id: String, app: AppState) async throws {
        guard let oldest = channels[id]?.messages.last?.ts else { return }
        let page = try await app.withSlack { try await $0.historyPage(id, before: oldest, limit: 20) }
        channels[id]?.takeEarlier(page)
    }

    /// The thread's replies, oldest first, read again; its parent in the channel follows.
    func thread(_ id: String, parent ts: String, app: AppState) async throws -> [SlackMessage] {
        let all = try await app.withSlack { try await $0.thread(id, threadTS: ts) }
        let replies = all.filter { $0.ts != ts }
        channels[id]?.takeThread(ts, parent: all.first { $0.ts == ts }, replies: replies)
        return replies
    }

    /// The replies held for a thread, to show while they are read again.
    func cachedThread(_ id: String, parent ts: String) -> [SlackMessage]? { channels[id]?.threads[ts] }

    // MARK: Changes made here

    /// A message was on screen in the room. True when it is newer than anything seen before.
    func seen(_ id: String, _ ts: String) -> Bool { channels[id]?.seen(ts) ?? false }

    /// The cursor was moved to `ts`, here.
    func setLastRead(_ id: String, _ ts: String) { channels[id]?.lastRead = ts }

    /// The viewer added or removed a reaction: that message changes, nothing is read again.
    func react(_ id: String, ts: String, name: String, on: Bool, user: String?) {
        channels[id]?.react(ts, name: name, on: on, user: user)
    }

    /// Another workspace, or none: nothing of the previous one stays.
    func reset() {
        channels = [:]; users = [:]; customEmoji = [:]; channelNames = [:]
    }
}

extension SlackReaction {
    /// `reactions` after `user` added (`on`) or removed their reaction `name`. Already in the
    /// wanted state: unchanged. A reaction nobody holds any more goes away.
    static func toggled(_ reactions: [SlackReaction]?, name: String, on: Bool, user: String?) -> [SlackReaction] {
        var out = reactions ?? []
        if let i = out.firstIndex(where: { $0.name == name }) {
            var r = out[i]
            var users = r.users ?? []
            let mine = user.map(users.contains) ?? false
            guard on != mine else { return out }
            r.count += on ? 1 : -1
            if on { if let user { users.append(user) } } else { users.removeAll { $0 == user } }
            r.users = users
            if r.count <= 0 { out.remove(at: i) } else { out[i] = r }
        } else if on {
            out.append(SlackReaction(name: name, count: 1, users: user.map { [$0] }))
        }
        return out
    }
}
