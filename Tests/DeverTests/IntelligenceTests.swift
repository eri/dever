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


