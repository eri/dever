import XCTest
@testable import Dever

final class SlackChannelTests: XCTestCase {
    private func message(_ ts: String, user: String = "U1", text: String = "hello", subtype: String? = nil,
                         replies: Int? = nil, latestReply: String? = nil, reactions: [SlackReaction]? = nil) -> SlackMessage {
        SlackMessage(ts: ts, user: user, text: text, reply_count: replies, latest_reply: latestReply, subtype: subtype,
                     reactions: reactions)
    }

    private func page(_ ts: [String], more: Bool = false) -> SlackHistoryPage {
        SlackHistoryPage(messages: ts.map { message($0) }, hasMore: more)
    }

    // MARK: Messages

    func testMergeKeepsNewestFirstAndReplacesByTS() {
        var channel = SlackStore.Channel()
        channel.merge([message("3.0"), message("1.0"), message("2.0", text: "before")])
        channel.merge([message("2.0", text: "edited"), message("4.0")])
        XCTAssertEqual(channel.messages.map(\.ts), ["4.0", "3.0", "2.0", "1.0"])
        XCTAssertEqual(channel.messages[2].text, "edited")
    }

    func testJoinsAndLeavesAreLeftOut() {
        var channel = SlackStore.Channel()
        channel.merge([message("1.0"), message("2.0", subtype: "channel_join"), message("3.0", subtype: "channel_leave")])
        XCTAssertEqual(channel.messages.map(\.ts), ["1.0"])
    }

    func testARefreshNeverDropsEarlierPages() {
        // Timestamps as Slack writes them: seconds since 1970, all the same width.
        func ts(_ n: Int) -> String { "17000000\(n + 10).000100" }
        var channel = SlackStore.Channel()
        channel.takeLatest(page((21...40).map(ts), more: true))
        XCTAssertTrue(channel.hasEarlier)
        channel.takeEarlier(page((1...20).map(ts), more: false))
        XCTAssertEqual(channel.messages.count, 40)
        XCTAssertFalse(channel.hasEarlier)
        // The latest page again, with one new message: the earlier pages stay, and its
        // "has more" does not bring back a "Show earlier" that has nothing to show.
        channel.takeLatest(page((22...41).map(ts), more: true))
        XCTAssertEqual(channel.messages.count, 41)
        XCTAssertEqual(channel.messages.first?.ts, ts(41))
        XCTAssertEqual(channel.messages.last?.ts, ts(1))
        XCTAssertFalse(channel.hasEarlier)
    }

    func testAShortChannelHasNothingEarlier() {
        var channel = SlackStore.Channel()
        channel.takeLatest(page(["1.0", "2.0"], more: false))
        XCTAssertFalse(channel.hasEarlier)
    }

    // MARK: Read cursor

    func testSeenOnlyMovesForward() {
        var channel = SlackStore.Channel()
        XCTAssertTrue(channel.seen("5.0"))
        XCTAssertFalse(channel.seen("3.0"))
        XCTAssertFalse(channel.seen("5.0"))
        XCTAssertTrue(channel.seen("6.0"))
        XCTAssertEqual(channel.seenUpTo, "6.0")
    }

    func testCursorToPushIsTheSeenMessagePastTheCursor() {
        var channel = SlackStore.Channel()
        XCTAssertNil(channel.cursorToPush)
        _ = channel.seen("5.0")
        XCTAssertEqual(channel.cursorToPush, "5.0")        // no cursor known yet: push
        channel.lastRead = "7.0"
        XCTAssertNil(channel.cursorToPush)                 // already read further, in Slack
        _ = channel.seen("9.0")
        XCTAssertEqual(channel.cursorToPush, "9.0")
        channel.lastRead = "9.0"
        XCTAssertNil(channel.cursorToPush)
    }

    func testAStaleCursorFromSlackDoesNotUndoWhatWasSeenHere() {
        var channel = SlackStore.Channel()
        _ = channel.seen("9.0")
        channel.cursor(fromSlack: "4.0")
        XCTAssertEqual(channel.lastRead, "9.0")
        channel.cursor(fromSlack: "12.0")                  // read further in Slack itself
        XCTAssertEqual(channel.lastRead, "12.0")
        var fresh = SlackStore.Channel()
        fresh.cursor(fromSlack: "4.0")
        XCTAssertEqual(fresh.lastRead, "4.0")
    }

    func testACursorMovedBackInSlackWins() {
        var channel = SlackStore.Channel()
        channel.cursor(fromSlack: "4.0")
        _ = channel.seen("9.0")
        channel.cursor(fromSlack: "4.0")                   // Slack has not caught up: what was seen stays
        XCTAssertEqual(channel.lastRead, "9.0")
        channel.cursor(fromSlack: "9.0")                   // it has
        channel.cursor(fromSlack: "6.0")                   // "Mark unread" in Slack, from message 7
        XCTAssertEqual(channel.lastRead, "6.0")
        XCTAssertNil(channel.seenUpTo)
        XCTAssertNil(channel.cursorToPush, "nothing here pushes the cursor forward again")
        _ = channel.seen("8.0")                            // read again here
        XCTAssertEqual(channel.cursorToPush, "8.0")
    }

    func testMarkUnreadInSlackRightAfterReadingHereWins() {
        var channel = SlackStore.Channel()
        channel.cursor(fromSlack: "4.0")
        _ = channel.seen("9.0")
        let then = Date(timeIntervalSince1970: 1_000)
        channel.moveCursor(to: "9.0", now: then)           // pushed to Slack from here
        channel.cursor(fromSlack: "4.0", now: then.addingTimeInterval(2))   // Slack has not caught up yet
        XCTAssertEqual(channel.lastRead, "9.0")
        channel.cursor(fromSlack: "6.0", now: then.addingTimeInterval(30))  // "Mark unread" there, later
        XCTAssertEqual(channel.lastRead, "6.0")
    }

    func testACursorMovedBackBeforeSlackCaughtUpStillWins() {
        var channel = SlackStore.Channel()
        channel.cursor(fromSlack: "4.0")
        _ = channel.seen("9.0")
        channel.cursor(fromSlack: "2.0")                   // older than anything Slack gave: moved back there
        XCTAssertEqual(channel.lastRead, "2.0")
    }

    func testMarkAllReadGoesPastTheNewestThreadReply() {
        var channel = SlackStore.Channel()
        XCTAssertNil(channel.readAllTarget)
        channel.merge([message("5.0"), message("3.0", replies: 2, latestReply: "8.5"), message("1.0", replies: 1, latestReply: "2.0")])
        XCTAssertEqual(channel.readAllTarget, "8.5")
        channel.merge([message("9.0")])
        XCTAssertEqual(channel.readAllTarget, "9.0")
    }

    // MARK: Threads

    func testAThreadUpdatesItsParentInPlace() {
        var channel = SlackStore.Channel()
        channel.merge([message("5.0"), message("3.0", text: "parent", replies: 1, latestReply: "3.5")])
        let parent = message("3.0", text: "parent as replies return it", replies: 2, latestReply: "6.0")
        channel.takeThread("3.0", parent: parent, replies: [message("3.5"), message("6.0")])
        XCTAssertEqual(channel.threads["3.0"]?.map(\.ts), ["3.5", "6.0"])
        XCTAssertEqual(channel.messages.map(\.ts), ["5.0", "3.0"])
        XCTAssertEqual(channel.messages[1].reply_count, 2)
        XCTAssertEqual(channel.messages[1].latest_reply, "6.0")
        // Only the counts follow: the message itself is the channel's.
        XCTAssertEqual(channel.messages[1].text, "parent")
    }

    func testAThreadWhoseParentIsNotHeldIsStillKept() {
        var channel = SlackStore.Channel()
        channel.takeThread("3.0", parent: message("3.0"), replies: [message("3.5")])
        XCTAssertEqual(channel.threads["3.0"]?.count, 1)
        XCTAssertTrue(channel.messages.isEmpty)
    }

    // MARK: Reactions

    func testReactionToggles() {
        let none: [SlackReaction]? = nil
        let added = SlackReaction.toggled(none, name: "+1", on: true, user: "ME")
        XCTAssertEqual(added, [SlackReaction(name: "+1", count: 1, users: ["ME"])])
        // Already there: unchanged, so the store agrees with the row's own optimistic toggle.
        XCTAssertEqual(SlackReaction.toggled(added, name: "+1", on: true, user: "ME"), added)
        let joined = SlackReaction.toggled([SlackReaction(name: "+1", count: 2, users: ["A", "B"])], name: "+1", on: true, user: "ME")
        XCTAssertEqual(joined, [SlackReaction(name: "+1", count: 3, users: ["A", "B", "ME"])])
        let left = SlackReaction.toggled(joined, name: "+1", on: false, user: "ME")
        XCTAssertEqual(left, [SlackReaction(name: "+1", count: 2, users: ["A", "B"])])
        // Removing the last one removes the pill; removing one never given changes nothing.
        XCTAssertEqual(SlackReaction.toggled(added, name: "+1", on: false, user: "ME"), [])
        XCTAssertEqual(SlackReaction.toggled(left, name: "+1", on: false, user: "ME"), left)
        XCTAssertEqual(SlackReaction.toggled(left, name: "heart", on: false, user: "ME"), left)
    }

    func testAReactionChangesOneMessageInTheChannelOrInAThread() {
        var channel = SlackStore.Channel()
        channel.merge([message("5.0"), message("3.0")])
        channel.takeThread("3.0", parent: nil, replies: [message("3.5")])
        channel.react("5.0", name: "tada", on: true, user: "ME")
        channel.react("3.5", name: "eyes", on: true, user: "ME")
        XCTAssertEqual(channel.messages[0].reactions?.map(\.name), ["tada"])
        XCTAssertNil(channel.messages[1].reactions)
        XCTAssertEqual(channel.threads["3.0"]?[0].reactions?.map(\.name), ["eyes"])
        channel.react("5.0", name: "tada", on: false, user: "ME")
        XCTAssertEqual(channel.messages[0].reactions, [])
    }
}

@MainActor
final class SlackStoreTests: XCTestCase {
    func testAnUnknownChannelIsQuiet() {
        let store = SlackStore()
        XCTAssertFalse(store.seen("C1", "5.0"))
        XCTAssertNil(store.cachedThread("C1", parent: "1.0"))
        store.setLastRead("C1", "5.0")
        store.react("C1", ts: "1.0", name: "+1", on: true, user: "ME")
        XCTAssertTrue(store.channels.isEmpty)
    }
}
