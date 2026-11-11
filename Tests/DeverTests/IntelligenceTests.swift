import XCTest
@testable import Dever

/// A model that answers what it is told, counts what it is asked, and can be held busy.
private final class FakeModel: LanguageModel, @unchecked Sendable {
    var availability: IntelligenceAvailability = .available
    var contextSize = 4096
    private let lock = NSLock()
    private var running = 0
    private(set) var peak = 0
    private(set) var order: [String] = []

    func tokenCount(_ text: String) async -> Int { TextBudget.estimate(text) }

    func respond(instructions: String, prompt: String, maximumTokens: Int?) async throws -> String {
        lock.withLock { running += 1; peak = max(peak, running); order.append(prompt) }
        try await Task.sleep(nanoseconds: 20_000_000)
        lock.withLock { running -= 1 }
        return "answer to \(prompt)"
    }

    var summary = MessageSummaryAnswer(kind: "Update", summary: "A summary.")
    func summarise(instructions: String, prompt: String) async throws -> MessageSummaryAnswer {
        lock.withLock { order.append(prompt) }
        return summary
    }

}

final class IntelligenceQueueTests: XCTestCase {
    func testOneGenerationAtATime() async throws {
        let model = FakeModel()
        let intelligence = Intelligence(model: model)
        try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try await intelligence.perform(.background) { try await $0.respond(instructions: "", prompt: "\(i)", maximumTokens: nil) }
                }
            }
            for try await _ in group {}
        }
        XCTAssertEqual(model.peak, 1)
        XCTAssertEqual(model.order.count, 5)
    }

    func testOnScreenGoesBeforeBackgroundAlreadyWaiting() async throws {
        let model = FakeModel()
        let intelligence = Intelligence(model: model)
        let ask: @Sendable (Intelligence.Priority, String) async throws -> String = { priority, prompt in
            try await intelligence.perform(priority) { try await $0.respond(instructions: "", prompt: prompt, maximumTokens: nil) }
        }
        async let first = ask(.background, "running")
        try await Task.sleep(nanoseconds: 5_000_000)
        async let second = ask(.background, "background")
        try await Task.sleep(nanoseconds: 5_000_000)
        async let third = ask(.onScreen, "on screen")
        _ = try await (first, second, third)
        XCTAssertEqual(model.order, ["running", "on screen", "background"])
    }

    func testUnavailableModelIsNeverAsked() async {
        let model = FakeModel()
        model.availability = .notReady
        let intelligence = Intelligence(model: model)
        do {
            _ = try await intelligence.perform(.onScreen) { try await $0.respond(instructions: "", prompt: "x", maximumTokens: nil) }
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? IntelligenceError, .unavailable)
        }
        XCTAssertTrue(model.order.isEmpty)
    }
}

final class TextBudgetTests: XCTestCase {
    func testEverythingFits() {
        XCTAssertEqual(TextBudget.newestThatFit(["a", "b", "c"], costs: [10, 10, 10], room: 30), ["a", "b", "c"])
    }

    func testKeepsTheNewestInOrder() {
        XCTAssertEqual(TextBudget.newestThatFit(["a", "b", "c", "d"], costs: [10, 10, 10, 10], room: 25), ["c", "d"])
    }

    func testStopsAtTheFirstThatDoesNotFitRatherThanSkippingIt() {
        // A hole in the middle of a conversation reads as a different conversation.
        XCTAssertEqual(TextBudget.newestThatFit(["a", "b", "c"], costs: [5, 50, 10], room: 20), ["c"])
    }

    func testRequiredHeadIsKeptWithTheNewest() {
        XCTAssertEqual(TextBudget.newestThatFit(["parent", "r1", "r2", "r3"], costs: [20, 10, 10, 10], room: 40, required: 1),
                       ["parent", "r2", "r3"])
    }

    func testNothingWhenTheRequiredHeadAloneDoesNotFit() {
        XCTAssertNil(TextBudget.newestThatFit(["description", "c1"], costs: [100, 5], room: 40, required: 1))
    }

    func testRoomLeavesInstructionsAndAnswer() {
        XCTAssertEqual(TextBudget.room(contextSize: 4096, instructions: 96, reserve: 400), 3600)
        XCTAssertEqual(TextBudget.room(contextSize: 0, instructions: 96), 0)
    }

    func testLanguageOfText() {
        XCTAssertEqual(Intelligence.language(of: "La migration ne remplit pas la colonne pour les anciens comptes, il faut la relancer."), "fr")
        XCTAssertEqual(Intelligence.language(of: "The migration leaves the column empty for older accounts, it has to run again."), "en")
    }
}

@MainActor
final class IntelligenceStoreTests: XCTestCase {
    private let subject = IntelligenceStore.Subject(feature: .messageSummary, id: "channel")
    private func text(_ s: String) -> GeneratedText { GeneratedText(sentences: [.init(text: s)]) }

    func testWritesOncePerVersion() async {
        let store = IntelligenceStore()
        store.isOn = { _ in true }
        var calls = 0
        let write: @Sendable () async throws -> GeneratedText = { await MainActor.run { calls += 1 }; return GeneratedText(sentences: [.init(text: "one")]) }
        store.want(subject, version: "1", write: write)
        XCTAssertTrue(store.isWriting(subject))
        await store.settle()
        store.want(subject, version: "1", write: write)
        await store.settle()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.text(subject), text("one"))
        XCTAssertFalse(store.isWriting(subject))
    }

    func testAPlaceKnowsWhetherItsTextIsPendingOrGivenUp() async {
        let store = IntelligenceStore()
        store.isOn = { _ in true }
        XCTAssertFalse(store.isPending(subject))
        store.want(subject, version: "1") { GeneratedText(sentences: [.init(text: "one")]) }
        XCTAssertTrue(store.isPending(subject))
        await store.settle()
        XCTAssertFalse(store.isPending(subject))
        XCTAssertFalse(store.isSilent(subject))
        store.want(subject, version: "2") { throw IntelligenceError.unavailable }
        XCTAssertTrue(store.isPending(subject), "pending over the older text too: the block says it is rewritten")
        await store.settle()
        XCTAssertTrue(store.isSilent(subject), "silence gives the place back to the message")
        XCTAssertFalse(store.isPending(subject))
    }

    func testOlderTextStaysWhileTheNewerIsWritten() async {
        let store = IntelligenceStore()
        store.isOn = { _ in true }
        store.want(subject, version: "1") { GeneratedText(sentences: [.init(text: "one")]) }
        await store.settle()
        store.want(subject, version: "2") { GeneratedText(sentences: [.init(text: "two")]) }
        XCTAssertEqual(store.text(subject), text("one"))
        XCTAssertFalse(store.isWriting(subject), "no skeleton over a text that is already there")
        await store.settle()
        XCTAssertEqual(store.text(subject), text("two"))
    }

    func testFailureIsSilentAndNotRetriedForTheSameInput() async {
        struct Refused: Error {}
        let store = IntelligenceStore()
        store.isOn = { _ in true }
        var calls = 0
        let write: @Sendable () async throws -> GeneratedText = { await MainActor.run { calls += 1 }; throw Refused() }
        store.want(subject, version: "1", write: write)
        await store.settle()
        store.want(subject, version: "1", write: write)
        await store.settle()
        XCTAssertEqual(calls, 1)
        XCTAssertNil(store.text(subject))
        XCTAssertEqual(store.entries[subject]?.silent, true)
        store.want(subject, version: "2") { GeneratedText(sentences: [.init(text: "two")]) }
        await store.settle()
        XCTAssertEqual(store.text(subject), text("two"))
    }

    func testEmptyAnswerIsSilence() async {
        let store = IntelligenceStore()
        store.isOn = { _ in true }
        store.want(subject, version: "1") { GeneratedText(sentences: [.init(text: "  ")]) }
        await store.settle()
        XCTAssertNil(store.text(subject))
    }

    func testSwitchedOffWritesNothingAndDropsWhatWasWritten() async {
        let store = IntelligenceStore()
        var on = true
        store.isOn = { _ in on }
        store.want(subject, version: "1") { GeneratedText(sentences: [.init(text: "one")]) }
        await store.settle()
        on = false
        var calls = 0
        store.want(subject, version: "2") { await MainActor.run { calls += 1 }; return GeneratedText(sentences: [.init(text: "two")]) }
        await store.settle()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(store.text(subject))
    }

    func testDroppingAFeatureLeavesTheOthers() async {
        let store = IntelligenceStore()
        store.isOn = { _ in true }
        let other = IntelligenceStore.Subject(feature: .issueSummary, id: "issue")
        store.want(subject, version: "1") { GeneratedText(sentences: [.init(text: "one")]) }
        store.want(other, version: "1") { GeneratedText(sentences: [.init(text: "issue")]) }
        await store.settle()
        store.drop(.messageSummary)
        XCTAssertNil(store.text(subject))
        XCTAssertEqual(store.text(other), text("issue"))
    }

    func testPreferencesDefaultOnAndSourceLanguage() {
        let defaults = UserDefaults(suiteName: "intelligence-tests-\(UUID().uuidString)")!
        XCTAssertTrue(IntelligencePreferences.isOn(.messageSummary, defaults: defaults))
        defaults.set(false, forKey: IntelligenceFeature.messageSummary.settingKey)
        XCTAssertFalse(IntelligencePreferences.isOn(.messageSummary, defaults: defaults))
        let french = "On attend ta réponse sur le front avant midi pour savoir si on livre aujourd'hui."
        XCTAssertEqual(IntelligencePreferences.language(forSummaryOf: french, defaults: defaults), "fr")
        defaults.set("english", forKey: IntelligencePreferences.summaryLanguageKey)
        XCTAssertEqual(IntelligencePreferences.language(forSummaryOf: french, defaults: defaults), "en")
    }
}

/// The real model, on a Mac that has it: `DEVER_TEST_REAL_MODEL=1 swift test --filter RealModel`.
/// Skipped everywhere else; it checks the shape of the answers, not their words.
final class RealModelTests: XCTestCase {}



final class MessageSummaryTests: XCTestCase {
    private let users = ["U1": SlackUser(id: "U1", name: "Alex", avatar: nil, isBot: false)]
    private let long = String(repeating: "Le rapport de QA couvre tous les critères d'acceptation. ", count: 8)

    func testOnlyAMessageTheRailCutsIsSummarised() {
        let short = SlackMessage(ts: "1", user: "U1", text: "Ok pour moi.")
        XCTAssertNil(MessageSummary.input(short, users: users, languageCode: { _ in "fr" }))
        var system = SlackMessage(ts: "2", user: "U1", text: long)
        system.subtype = "channel_topic"
        XCTAssertNil(MessageSummary.input(system, users: users, languageCode: { _ in "fr" }))
        let input = MessageSummary.input(SlackMessage(ts: "3", user: "U1", text: long), users: users, languageCode: { _ in "fr" })
        XCTAssertEqual(input?.author, "Alex")
        XCTAssertEqual(input?.language, "French")
    }

    func testThePlaceIsHeldOnlyForAMessageThatWillBeSummarised() {
        let message = SlackMessage(ts: "1", user: "U1", text: long)
        XCTAssertTrue(MessageSummary.isSummarised(message, users: users))
        XCTAssertNotNil(MessageSummary.input(message, users: users, languageCode: { _ in "fr" }))
        // Long as Slack sends it, short once its link is read as its label: no summary, no held place.
        let link = SlackMessage(ts: "2", user: "U1", text: "Le rapport : <https://example.com/\(String(repeating: "a", count: 260))|ici>")
        XCTAssertTrue(MessageSummary.isLong(link))
        XCTAssertFalse(MessageSummary.isSummarised(link, users: users))
        XCTAssertNil(MessageSummary.input(link, users: users, languageCode: { _ in "fr" }))
        XCTAssertFalse(MessageSummary.isSummarised(SlackMessage(ts: "3", user: "U1", text: "Ok pour moi."), users: users))
    }

    func testTheExcerptIsTheMessagesOwnWordsWithoutItsMarks() {
        let message = SlackMessage(ts: "1", user: "U1", text: "*Rapport* de `QA` pour <@U1>\nsuite\n" + String(repeating: "mot ", count: 200))
        let excerpt = MessageSummary.excerpt(message, users: users)
        XCTAssertTrue(excerpt.hasPrefix("Rapport de QA pour @Alex suite mot"))
        XCTAssertEqual(excerpt.count, 400)
    }

    func testAnEditedMessageIsAnotherVersion() throws {
        let a = try XCTUnwrap(MessageSummary.input(SlackMessage(ts: "3", user: "U1", text: long), users: users, languageCode: { _ in "fr" }))
        let b = try XCTUnwrap(MessageSummary.input(SlackMessage(ts: "3", user: "U1", text: long + " Corrigé."), users: users, languageCode: { _ in "fr" }))
        XCTAssertNotEqual(a.version, b.version)
    }

    private func shown(_ summary: String, kind: String = "Update", original: String) -> GeneratedText? {
        MessageSummary.text(from: .init(kind: kind, summary: summary), original: original)
    }

    func testASummaryNearlyAsLongAsTheMessageIsNotShown() {
        XCTAssertNil(shown(String(long.prefix(230)), original: String(long.prefix(241))))
        XCTAssertNil(shown("  ", original: long))
        XCTAssertEqual(shown("le *rapport* couvre\ntous les critères.", original: long)?.sentences.map(\.text),
                       ["Le rapport couvre tous les critères."])
    }

    func testASummaryIsCutAtAWholeSentenceUnderTheLimit() {
        let original = String(repeating: long, count: 6)
        let first = "Le rapport de QA est terminé et vingt et un critères sur vingt-quatre passent sur la preview."
        let second = "SUP-931 est à corriger avant la mise en production, les deux autres peuvent attendre."
        let third = "Le détail complet des cas de test est dans le canvas du canal."
        XCTAssertEqual(shown("\(first) \(second) \(third)", original: original)?.sentences.map(\.text), ["\(first) \(second)"])
        XCTAssertNil(shown(String(repeating: "mot ", count: 80), original: original), "one endless sentence")
    }

    func testTheKindHeadsTheBlockAndIsNotRepeatedInTheSentence() {
        let text = shown("Request: get two screenshots of the feature before the weekly.", kind: "request", original: long)
        XCTAssertEqual(text?.kind, "Request")
        XCTAssertEqual(text?.sentences.map(\.text), ["Get two screenshots of the feature before the weekly."])
        XCTAssertNil(shown("Something else entirely.", kind: "Poem", original: long)?.kind)
        XCTAssertEqual(shown("The export leaves this release.", kind: "update", original: long)?.kind, "Update")
        XCTAssertEqual(MessageSummary.kinds, ["Request", "Question", "Problem", "Update"])
    }

    func testARequestInAMessageThatNamesTheReaderIsForThem() {
        let users = ["U1": SlackUser(id: "U1", name: "Alex", avatar: nil, isBot: false),
                     "U2": SlackUser(id: "U2", name: "Sam Rivers", avatar: nil, isBot: false)]
        let named = SlackMessage(ts: "1", user: "U1", text: "il faudrait que Sam relise la migration")
        let mentioned = SlackMessage(ts: "2", user: "U1", text: "<@U2> tu peux relire ?")
        let other = SlackMessage(ts: "3", user: "U1", text: "Robin, tu peux relire ?")
        XCTAssertTrue(MessageSummary.isForReader(named, kind: "Request", me: "U2", users: users))
        XCTAssertTrue(MessageSummary.isForReader(mentioned, kind: "Question", me: "U2", users: users))
        XCTAssertFalse(MessageSummary.isForReader(other, kind: "Request", me: "U2", users: users))
        XCTAssertFalse(MessageSummary.isForReader(named, kind: "Problem", me: "U2", users: users), "a problem is not asked of anyone")
        XCTAssertFalse(MessageSummary.isForReader(named, kind: "Update", me: "U2", users: users))
        XCTAssertFalse(MessageSummary.isForReader(named, kind: "Request", me: nil, users: users))
        XCTAssertFalse(MessageSummary.names("samedi on livre", reader: "Sam Rivers"))
        XCTAssertFalse(MessageSummary.names("anything", reader: ""))
    }

    func testSubjectsAreOnePerMessage() {
        XCTAssertNotEqual(MessageSummary.subject(channel: "C1", ts: "1"), MessageSummary.subject(channel: "C1", ts: "2"))
        XCTAssertEqual(MessageSummary.subject(channel: "C1", ts: "1").feature, .messageSummary)
    }
}

extension RealModelTests {
    func testSummaryOfALongMessage() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEVER_TEST_REAL_MODEL"] == "1", "needs the system model")
        let report = """
        Hi team, final QA report for the tips feature (QA-27). Scope: all test cases executed, covering all 24 acceptance criteria. Tested on preview PR-4714 in the web extension and the back office. Result: 21 criteria pass, 3 fail. SUP-931: the tips list isn't refreshed after a language change, learners see and open tips in the previous language. SUP-928: visual flickering in the tip content text when toggling the favorite heart. SUP-929: sync latency of about 40 seconds for backend tip changes. None is blocking for the demo, but SUP-931 should be fixed before the release. Full report in the canvas.
        """
        let others = [
            ("Estelle", "Hey team, I have the customer weekly tomorrow at 11am and I'd love to show them what's coming with AI Tips. Could someone send me 2 or 3 screenshots of the feature in the web extension before tomorrow morning? Nothing fancy, the tip page and the success screen would be perfect. Thanks a lot!"),
            ("Marco", "Hi Kyryl, welcome! You can start testing AI tips. FYI: tips are a new kind of content we're pushing on Mendo. They are short, hands-on AI tips that learners validate with a 'Nailed it!' button to earn +2 XP. The acceptance criteria are in the Linear project and the preview is deployed on PR-4714. Ping me if anything is unclear."),
            ("Kyryl", "One more thing on sync: when I change a tip in the back office, it takes 1 to 2 minutes before the change shows in the web extension. It is not a bug strictly speaking, the cache is refreshed on a timer, but for editors it feels broken because they do not see their fix. I think we should decide whether we optimize for faster sync before the release or document the delay."),
        ]
        for (author, message) in others {
            let text = try await MessageSummary.write(.init(author: author, text: message, language: "English"))
            print("summary: [\(text.kind ?? "-")] \(text.sentences.first?.text ?? "")")
        }
        for language in ["English", "French"] {
            let start = Date()
            let text = try await MessageSummary.write(.init(author: "Kyryl", text: report, language: language))
            print("summary (\(language)) in \(String(format: "%.1f", Date().timeIntervalSince(start))) s: [\(text.kind ?? "-")] \(text.sentences.first?.text ?? "")")
            XCTAssertLessThanOrEqual(text.sentences.first?.text.count ?? .max, MessageSummary.longest)
        }
    }
}



final class DetectedMentionTests: XCTestCase {
    private let users = [
        "ME": SlackUser(id: "ME", name: "Sam Rivers", avatar: nil, isBot: false),
        "U1": SlackUser(id: "U1", name: "Alex Stone", avatar: nil, isBot: false),
        "B1": SlackUser(id: "B1", name: "Sam Bot", avatar: nil, isBot: true),
    ]
    private func message(_ ts: String, _ text: String, user: String = "U1") -> SlackMessage { SlackMessage(ts: ts, user: user, text: text) }
    private func found(_ text: String, users: [String: SlackUser]? = nil) -> Bool {
        !DetectedMention.find(in: [message("1", text)], me: "ME", users: users ?? self.users).isEmpty
    }

    func testAWordOfTheNameWhateverTheCaseAndTheAccents() {
        XCTAssertTrue(found("il faudrait que Sam relise la migration"))
        XCTAssertTrue(found("sam tu peux regarder ?"))
        XCTAssertTrue(found("c'est l'écran de Sam, non ?"))
        XCTAssertTrue(found("ask Rivers about it"))
        XCTAssertTrue(found("SAM!!"))
        var accented = users
        accented["ME"] = SlackUser(id: "ME", name: "Léa Martin", avatar: nil, isBot: false)
        XCTAssertTrue(found("on voit ça avec lea demain", users: accented))
        XCTAssertFalse(found("samedi on livre"), "part of a word is not the name")
        XCTAssertFalse(found("Robin, tu peux relire ?"))
    }

    func testARealMentionIsNeverDetectedToo() {
        XCTAssertFalse(found("<@ME> Sam, tu peux relire ?"))
        XCTAssertFalse(found("<@ME|sam> tu peux relire ?"))
        XCTAssertTrue(found("<@U1> demande à Sam"), "someone else's mention does not hide the name")
    }

    func testTheReadersOwnMessagesAreNotAboutThem() {
        XCTAssertTrue(DetectedMention.find(in: [message("1", "Sam here, I pushed the fix", user: "ME")], me: "ME", users: users).isEmpty)
    }

    func testANameSharedWithAColleagueNamesNoOne() {
        var two = users
        two["U2"] = SlackUser(id: "U2", name: "Sam Lee", avatar: nil, isBot: false)
        XCTAssertEqual(DetectedMention.words(reader: "ME", users: two), ["rivers"])
        XCTAssertFalse(found("Sam, tu peux relire ?", users: two))
        XCTAssertTrue(found("Rivers, tu peux relire ?", users: two))
        XCTAssertEqual(DetectedMention.words(reader: "ME", users: users), ["sam", "rivers"], "a bot of the same name does not count")
        two["ME"] = SlackUser(id: "ME", name: "Sam", avatar: nil, isBot: false)
        XCTAssertFalse(found("Sam, tu peux relire ?", users: two), "nothing left that names the reader alone")
    }

    func testShortWordsAndInitialsAreNotNames() {
        var short = users
        short["ME"] = SlackUser(id: "ME", name: "Jo C. de Luca", avatar: nil, isBot: false)
        XCTAssertEqual(DetectedMention.words(reader: "ME", users: short), ["luca"])
        XCTAssertTrue(DetectedMention.words(reader: "nobody", users: users).isEmpty)
    }

    func testANameThatIsAlsoAWordNeedsItsCapitalAndMoreAtTheHeadOfASentence() {
        var will = users
        will["ME"] = SlackUser(id: "ME", name: "Will Mark", avatar: nil, isBot: false)
        for text in ["it will break staging", "Will you merge this today?", "I will look. Will it pass?", "mark this as done please",
                     "Mark this as done please", "can mark take a look?", "first line\nWill it pass"] {
            XCTAssertFalse(found(text, users: will), text)
        }
        for text in ["ask Will about the migration", "Will, can you review #42?", "Mark: any idea?", "c'est Will qui a écrit cet écran",
                     "ok. Will, tu regardes ?"] {
            XCTAssertTrue(found(text, users: will), text)
        }
    }

    func testCodeLinksAndAddressesAreNotProse() {
        XCTAssertFalse(found("`git log --author=sam` shows nothing"))
        XCTAssertFalse(found("```\nowner: sam\n```"))
        XCTAssertFalse(found("see <https://example.com/users/sam/settings>"))
        XCTAssertFalse(found("mail <mailto:sam@example.com|sam@example.com>"))
        XCTAssertFalse(found("branch is in <#C1|sam-sandbox>"))
        XCTAssertFalse(found("https://example.com/sam is down"))
        XCTAssertTrue(found("see <https://example.com/doc|the doc Sam wrote>"))
    }

    func testNewestFirstWithAuthorAndPlainText() {
        let out = DetectedMention.find(in: [message("10.0", "Sam ?"), message("20.0", "ask <@U1> or Sam")], me: "ME", users: users)
        XCTAssertEqual(out.map(\.ts), ["20.0", "10.0"])
        XCTAssertEqual(out.first?.author, "Alex Stone")
        XCTAssertEqual(out.first?.text, "ask @Alex Stone or Sam")
    }

    private func snapshot() -> ProjectSnapshot {
        var s = ProjectSnapshot()
        let date = Date(timeIntervalSince1970: 100)
        s.slack = .init(unread: 4, firstUnreadTS: "1.0", lastUnreadAt: date,
                        mentions: [.init(ts: "4.0", author: "Alex", text: "@Sam Rivers look", date: date)],
                        detected: [.init(ts: "3.0", author: "Alex", text: "ask Sam", date: date)],
                        unreadTS: ["1.0", "2.0", "3.0", "4.0"])
        return s
    }

    func testDetectedItemsCountBesideMentionsAndNeverAsOne() {
        let items = snapshot().waiting(channel: "team", detected: true)
        XCTAssertEqual(items.map(\.kind), [.mention, .detected, .unread])
        XCTAssertEqual(items[1].target, .slack(ts: "3.0"))
        XCTAssertEqual(items[2].text, "2 more unread in #team")
        XCTAssertEqual(Set(items.map(\.id)).count, 3)
    }

    func testSwitchedOffTheyAreUnreadMessagesLikeTheOthers() {
        let items = snapshot().waiting(channel: "team")
        XCTAssertEqual(items.map(\.kind), [.mention, .unread])
        XCTAssertEqual(items[1].text, "3 more unread in #team")
    }

    @MainActor
    func testReadingTheChannelRemovesThem() {
        let store = OverviewStore()
        let id = UUID()
        store.setForTesting(snapshot(), for: id)
        store.slackRead(id, upTo: "3.0")
        XCTAssertEqual(store.snapshots[id]?.slack?.detected.count, 0)
        XCTAssertEqual(store.snapshots[id]?.slack?.mentions.count, 1)
        XCTAssertEqual(store.snapshots[id]?.slack?.unread, 1)
    }

    func testTheFeatureIsBuiltWithItsOwnSwitch() {
        XCTAssertTrue(IntelligenceFeature.built.contains(.detectedMentions))
        let defaults = UserDefaults(suiteName: "detected-\(UUID().uuidString)")!
        XCTAssertTrue(IntelligencePreferences.isOn(.detectedMentions, defaults: defaults))
        defaults.set(false, forKey: IntelligenceFeature.detectedMentions.settingKey)
        XCTAssertFalse(IntelligencePreferences.isOn(.detectedMentions, defaults: defaults))
        XCTAssertTrue(IntelligencePreferences.isOn(.messageSummary, defaults: defaults))
    }
}
