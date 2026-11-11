import XCTest
@testable import Dever

/// The Overview's "for you" items that come from a long Slack message (docs/on-device-ai.md, 5.7).
@MainActor
final class WaitingSummaryTests: XCTestCase {
    private let users = ["U1": SlackUser(id: "U1", name: "Alex", avatar: nil, isBot: false)]
    private let long = "<@U2> " + String(repeating: "Le rapport de QA couvre tous les critères d'acceptation. ", count: 8)

    private func mention(_ ts: String, _ text: String) -> ProjectSnapshot.SlackStats.Mention {
        .init(SlackMessage(ts: ts, user: "U1", text: text), users: users, languageCode: { _ in "fr" })
    }

    private func snapshot(_ mentions: [ProjectSnapshot.SlackStats.Mention]) -> ProjectSnapshot {
        var s = ProjectSnapshot()
        s.slack = .init(unread: mentions.count, mentions: mentions)
        return s
    }

    func testOnlyALongMentionCarriesASummary() {
        let items = snapshot([mention("2", long), mention("1", "<@U2> ok pour toi ?")]).waiting(channel: "team", channelID: "C1")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].summary?.subject, MessageSummary.subject(channel: "C1", ts: "2"))
        XCTAssertEqual(items[0].author, "Alex")
        XCTAssertNil(items[1].summary, "a short message is never summarised")
        // The line keeps the message's own words until a summary is there.
        XCTAssertTrue(items[0].text.hasPrefix("Alex: @U2 Le rapport"))
    }

    func testTheEntryIsTheOneTheRailWrites() throws {
        let message = SlackMessage(ts: "2", user: "U1", text: long)
        let rail = try XCTUnwrap(MessageSummary.input(message, users: users, languageCode: { _ in "fr" }))
        let item = try XCTUnwrap(snapshot([mention("2", long)]).waiting(channel: "team", channelID: "C1").first)
        XCTAssertEqual(item.summary?.input, rail)
        XCTAssertEqual(item.summary?.input.version, rail.version, "same version: a summary the rail wrote is not written again")
    }

    func testNoChannelIdNoSummary() {
        XCTAssertNil(snapshot([mention("2", long)]).waiting(channel: "team").first?.summary)
    }

    func testReviewsAndTheUnreadLineAreNeverSummarised() {
        var s = snapshot([])
        s.slack = .init(unread: 4, firstUnreadTS: "1", lastUnreadAt: Date())
        s.github = .init(reviewRequests: [.init(number: 1, title: String(repeating: "long title ", count: 40), url: "u", issue: nil, date: Date())])
        XCTAssertTrue(s.waiting(channel: "team", channelID: "C1").allSatisfy { $0.summary == nil })
    }

    func testAsksForTheNewestFirstAndNoMoreThanTheCap() {
        let now = Date()
        let input = MessageSummary.Input(author: "Alex", text: long, language: "French")
        func item(_ n: Int, long: Bool = true) -> WaitingItem {
            WaitingItem(kind: .mention, text: "t", date: now.addingTimeInterval(Double(n)), target: .slack(ts: "\(n)"), author: "Alex",
                        summary: long ? .init(subject: MessageSummary.subject(channel: "C1", ts: "\(n)"), input: input) : nil)
        }
        let asked = WaitingItem.toSummarise([item(1), item(9, long: false)] + (2...8).map { item($0) })
        XCTAssertEqual(asked.count, WaitingItem.mostSummaries)
        XCTAssertEqual(asked.map(\.target), (0..<WaitingItem.mostSummaries).map { .slack(ts: "\(8 - $0)") })
    }

    func testTheLineIsTheSummaryOnlyOnceWritten() throws {
        let item = try XCTUnwrap(snapshot([mention("2", long)]).waiting(channel: "team", channelID: "C1").first)
        XCTAssertNil(item.summarised(by: nil), "being written, or silence: the excerpt stays")
        XCTAssertNil(item.summarised(by: GeneratedText(sentences: [.init(text: " ")])))
        let shown = try XCTUnwrap(item.summarised(by: GeneratedText(sentences: [.init(text: "Le rapport passe.")], kind: "Update")))
        XCTAssertEqual(shown.kind, "Update")
        XCTAssertEqual(shown.sentence, "Le rapport passe.")
        let short = try XCTUnwrap(snapshot([mention("1", "<@U2> ok ?")]).waiting(channel: "team", channelID: "C1").first)
        XCTAssertNil(short.summarised(by: MessageSummary.sample), "a short message keeps its words whatever the store holds")
    }

    func testASummaryTheRailWroteCostsNothing() async throws {
        let store = IntelligenceStore()
        store.isOn = { _ in true }
        let item = try XCTUnwrap(snapshot([mention("2", long)]).waiting(channel: "team", channelID: "C1").first)
        let summary = try XCTUnwrap(item.summary)
        // The rail, first.
        store.want(MessageSummary.subject(channel: "C1", ts: "2"), version: summary.input.version) { MessageSummary.sample }
        await store.settle()
        // Then the Overview, for the same message.
        let again = expectation(description: "written again")
        again.isInverted = true
        store.want(summary.subject, version: summary.input.version) { again.fulfill(); return MessageSummary.sample }
        await store.settle()
        await fulfillment(of: [again], timeout: 0.2)
        XCTAssertEqual(item.summarised(by: store.text(summary.subject))?.kind, "Problem")
    }
}
