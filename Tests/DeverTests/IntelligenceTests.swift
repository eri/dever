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

    var failure = FailureAnswer(stated: true, line: "", sentence: "")
    private(set) var failurePrompts: [String] = []
    func explainFailure(instructions: String, prompt: String) async throws -> FailureAnswer {
        lock.withLock { failurePrompts.append(prompt) }
        return failure
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

    func testASummaryKeptOnDiskIsNotWrittenAgain() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dever-summaries-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let message = MessageSummary.subject(channel: "C1", ts: "200.000100")
        let first = IntelligenceStore(cache: SummaryCache(url: url))
        first.isOn = { _ in true }
        first.want(message, version: "1") { GeneratedText(sentences: [.init(text: "one")], kind: "Problem") }
        await first.settle()

        // Another launch: the same input is read from the file, the model is not asked.
        let second = IntelligenceStore(cache: SummaryCache(url: url))
        second.isOn = { _ in true }
        second.want(message, version: "1") { XCTFail("written again"); throw IntelligenceError.unavailable }
        XCTAssertEqual(second.text(message), GeneratedText(sentences: [.init(text: "one")], kind: "Problem"))
        XCTAssertFalse(second.isPending(message))
        // An edited message is written again.
        second.want(message, version: "2") { GeneratedText(sentences: [.init(text: "two")]) }
        XCTAssertTrue(second.isPending(message))
        await second.settle()
        XCTAssertEqual(SummaryCache(url: url).record(message.id, version: "2")?.sentence, "two")
    }

    func testSilenceIsKeptTooAndOtherFeaturesStayInMemory() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dever-summaries-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = IntelligenceStore(cache: SummaryCache(url: url))
        store.isOn = { _ in true }
        let message = MessageSummary.subject(channel: "C1", ts: "200.000100")
        let issue = IntelligenceStore.Subject(feature: .issueSummary, id: "C1/200.000100")
        store.want(message, version: "1") { throw IntelligenceError.unavailable }
        store.want(issue, version: "1") { GeneratedText(sentences: [.init(text: "issue")]) }
        await store.settle()
        let kept = SummaryCache(url: url)
        XCTAssertEqual(kept.records.count, 1)
        XCTAssertNotNil(kept.record(message.id, version: "1"))
        XCTAssertNil(kept.record(message.id, version: "1")?.text, "silence: not asked again at the next launch")
    }

    func testAReadMessagesSummaryLeavesTheDisk() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dever-summaries-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = IntelligenceStore(cache: SummaryCache(url: url))
        store.isOn = { _ in true }
        let old = MessageSummary.subject(channel: "C1", ts: "100.000000")
        let new = MessageSummary.subject(channel: "C1", ts: "300.000000")
        let other = MessageSummary.subject(channel: "C2", ts: "100.000000")
        for subject in [old, new, other] { store.want(subject, version: "1") { GeneratedText(sentences: [.init(text: "s")]) } }
        await store.settle()
        store.read(channel: "C1", upTo: "200.000000")
        XCTAssertEqual(Set(SummaryCache(url: url).records.keys), [new.id, other.id])
        XCTAssertNotNil(store.text(old), "what is on screen stays until the app quits")
        // A summary written for a message already read is not kept at all.
        let late = MessageSummary.subject(channel: "C1", ts: "150.000000")
        store.want(late, version: "1") { GeneratedText(sentences: [.init(text: "late")]) }
        await store.settle()
        XCTAssertNil(SummaryCache(url: url).records[late.id])
        // The switch turned off: nothing stays.
        store.drop(.messageSummary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testNothingStaysOnDiskPastTheLimit() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dever-summaries-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        var cache = SummaryCache(url: url)
        cache.save("C1/1", version: "1", text: GeneratedText(sentences: [.init(text: "old")]), now: now.addingTimeInterval(-15 * 86_400))
        cache.save("C1/2", version: "1", text: GeneratedText(sentences: [.init(text: "recent")]), now: now.addingTimeInterval(-2 * 86_400))
        let loaded = SummaryCache(url: url, now: now, maxAge: 14 * 86_400)
        XCTAssertEqual(Array(loaded.records.keys), ["C1/2"])
        XCTAssertEqual(Array(SummaryCache(url: url, now: now, maxAge: .infinity).records.keys), ["C1/2"], "and the file was rewritten")
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

    func testAnEditedMessageIsAnotherVersion() throws {
        let a = try XCTUnwrap(MessageSummary.input(SlackMessage(ts: "3", user: "U1", text: long), users: users, languageCode: { _ in "fr" }))
        let b = try XCTUnwrap(MessageSummary.input(SlackMessage(ts: "3", user: "U1", text: long + " Corrigé."), users: users, languageCode: { _ in "fr" }))
        XCTAssertNotEqual(a.version, b.version)
        // The same at every launch, so a summary kept on disk is found again.
        XCTAssertEqual(MessageSummary.Input(author: "A", text: "abc", language: "French").version, "\(MessageSummary.revision)-French-3-ba7816bf8f01cfea")
    }

    private func shown(_ summary: String, kind: String = "Update", original: String) -> GeneratedText? {
        MessageSummary.text(from: .init(kind: kind, summary: summary), original: original)
    }

    func testASummaryNearlyAsLongAsTheMessageIsNotShown() {
        let sentence = "Le rapport de QA couvre tous les critères d'acceptation prévus pour cette version du produit et rien ne bloque."
        XCTAssertNil(shown(sentence, original: sentence + " Voilà, c'est tout pour aujourd'hui."))
        XCTAssertNil(shown("  ", original: long))
        XCTAssertEqual(shown("le *rapport* couvre\ntous les critères.", original: long)?.sentences.map(\.text),
                       ["Le rapport couvre tous les critères."])
    }

    func testASummaryIsCutAtAWholeSentenceUnderTheLimit() {
        let original = String(repeating: long, count: 6)
        let first = "Le rapport de QA est terminé et vingt et un critères sur vingt-quatre passent sur la preview."
        let second = "SUP-931 est à corriger avant la mise en production, les deux autres peuvent attendre."
        let third = "Le détail complet des cas de test est dans le canvas du canal."
        XCTAssertEqual(shown("\(first) \(second) \(third)", original: original)?.sentences.map(\.text), [first])
        XCTAssertEqual(shown("Le rapport est prêt. SUP-931 reste à corriger. Le détail est dans le canvas.", original: original)?.sentences.map(\.text),
                       ["Le rapport est prêt. SUP-931 reste à corriger. Le détail est dans le canvas."])
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




/// A job log as GitHub Actions writes it: the step's header, its output, the runner's error,
/// then the clean-up.
func actionsLog(command: String, output: [String], errors: [String] = ["Process completed with exit code 1."]) -> Data {
    var lines = ["##[group]Run actions/checkout@v4", "with:", "  fetch-depth: 1", "##[endgroup]", "Syncing repository",
                 "##[group]Run \(command)", "\(command)", "shell: /usr/bin/bash -e {0}", "env:", "  CI: true", "##[endgroup]"]
    lines += output
    lines += errors.map { "##[error]\($0)" }
    lines += ["Post job cleanup.", "[command]/usr/bin/git version", "git version 2.51.0", "Cleaning up orphan processes"]
    return Data(lines.enumerated().map { "2026-11-03T09:14:\(String(format: "%02d", $0.offset % 60)).1234567Z \($0.element)" }.joined(separator: "\n").utf8)
}

extension RealModelTests {
    /// Measurement: what the real model answers on failed steps, three times each, and what
    /// Dever would show once its checks have run. `DEVER_TEST_LOG_DIR` adds real log tails
    /// (one file each, as downloaded) to the made-up ones.
    func testWhyAStepFailed() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEVER_TEST_REAL_MODEL"] == "1", "needs the system model")
        // (name, the log states the error, job, step, log)
        var cases: [(String, Bool, String, String?, Data)] = [
            ("swift-test", true, "test (macos-15)", "Run tests", actionsLog(command: "swift test", output: [
                "[412/418] Compiling ReaderTests StreakCalendarTests.swift", "[418/418] Linking ReaderPackageTests", "Build complete! (48.21s)",
                "Test Suite 'All tests' started at 2026-11-03 09:14:02.118.", "Test Suite 'StreakCalendarTests' started at 2026-11-03 09:14:02.120.",
                "Test Case '-[ReaderTests.StreakCalendarTests testStreakSurvivesMidnight]' passed (0.004 seconds).",
                "Test Case '-[ReaderTests.StreakCalendarTests testStreakAcrossTimeZoneChange]' started.",
                "/Users/runner/work/reader/reader/Tests/ReaderTests/StreakCalendarTests.swift:88: error: -[ReaderTests.StreakCalendarTests testStreakAcrossTimeZoneChange] : XCTAssertEqual failed: (\"3\") is not equal to (\"4\") - streak should count the day in the new time zone",
                "Test Case '-[ReaderTests.StreakCalendarTests testStreakAcrossTimeZoneChange]' failed (0.012 seconds).",
                "Test Case '-[ReaderTests.StreakCalendarTests testEmptyHistory]' passed (0.001 seconds).",
                "Test Suite 'StreakCalendarTests' failed at 2026-11-03 09:14:02.160.", "\t Executed 3 tests, with 1 failure (0 unexpected) in 0.017 (0.040) seconds"])),
            ("typescript", true, "build-console", "Build", actionsLog(command: "npm run build", output: [
                "> teacher-console@3.4.0 build", "> tsc --noEmit && vite build", "",
                "npm warn deprecated inflight@1.0.6: This module is not supported, and leaks memory.",
                "npm warn deprecated glob@7.2.3: Glob versions prior to v9 are no longer supported",
                "src/screens/Results/ExportButton.tsx:42:27 - error TS2345: Argument of type 'string | undefined' is not assignable to parameter of type 'string'.",
                "  Type 'undefined' is not assignable to type 'string'.", "", "42     downloadPdf(classId, selectedTerm);", "                             ~~~~~~~~~~~~", "",
                "Found 1 error in src/screens/Results/ExportButton.tsx:42"], errors: ["Process completed with exit code 2."])),
            ("waits-then-exits", false, "deploy-preview", "Deploy", actionsLog(command: "./scripts/deploy-preview.sh pr-2207", output: [
                "Preparing bundle for pr-2207", "Uploading 214 files to preview storage", "Upload complete (38.4 MB)", "Requesting preview environment pr-2207",
                "Waiting for environment to become ready", "Waiting for environment to become ready", "Waiting for environment to become ready", "Waiting for environment to become ready"])),
            ("time-limit", true, "e2e (tablet)", "Run Playwright", actionsLog(command: "npx playwright test --project=tablet", output: [
                "  Running 64 tests using 4 workers", "  ✓  1 [tablet] › library.spec.ts:12:5 › opens the library (2.1s)", "  ✓  2 [tablet] › library.spec.ts:30:5 › filters by level (1.8s)",
                "  ✓  3 [tablet] › reader.spec.ts:9:5 › opens a book (3.0s)", "  ✓  4 [tablet] › reader.spec.ts:41:5 › plays audio (5.2s)",
                "  ✓  5 [tablet] › streaks.spec.ts:8:5 › shows the calendar (1.4s)", "  ✓  6 [tablet] › streaks.spec.ts:26:5 › shows the reward (1.9s)",
                "  ✓  7 [tablet] › offline.spec.ts:10:5 › downloads a book (8.8s)"],
                errors: ["The operation was canceled.", "The job running on runner hosted-agent-7 has exceeded the maximum execution time of 30 minutes."])),
            ("network-in-lint", true, "lint", "Install", actionsLog(command: "npm ci", output: [
                "npm warn deprecated rimraf@3.0.2: Rimraf versions prior to v4 are no longer supported",
                "npm warn deprecated eslint@8.57.1: This version is no longer supported. Please see https://eslint.org/version-support for other options.",
                "npm error code ECONNRESET", "npm error syscall read", "npm error errno ECONNRESET",
                "npm error network request to https://registry.npmjs.org/@typescript-eslint%2fparser failed, reason: read ECONNRESET",
                "npm error network This is a problem related to network connectivity.", "npm error network In most cases you are behind a proxy or have bad network settings.",
                "npm error A complete log of this run can be found in: /home/runner/.npm/_logs/2026-11-03T09_02_11_512Z-debug-0.log"])),
            ("format-diff", false, "Lint", "Check formatting", actionsLog(command: "pnpm format && git diff --exit-code", output: [
                "$ prettier --write .", "Finished in 118ms on 2591 files using 4 threads.", "diff --git a/docs/guide.md b/docs/guide.md", "index 06481aa..ae49612 100644",
                "--- a/docs/guide.md", "+++ b/docs/guide.md", "@@ -12,3 +12,3 @@ Install", "-Run  the installer", "+Run the installer"])),
            ("warnings-only", false, "build", "Build", actionsLog(command: "make release", output: [
                "cc -O2 -c src/main.c", "src/main.c:14:9: warning: unused variable 'n' [-Wunused-variable]", "cc -O2 -c src/io.c", "ld -o bin/app main.o io.o", "Packaging bin/app",
                "Uploading artifact"], errors: ["Process completed with exit code 137."])),
            ("pytest", true, "tests (3.12)", "pytest", actionsLog(command: "pytest -q", output: [
                "........F...                                                             [100%]", "=================================== FAILURES ===================================",
                "______________________________ test_invoice_total ______________________________", "", "    def test_invoice_total():", ">       assert total([Line(2, 9.99)]) == 19.98",
                "E       assert 19.97 == 19.98", "", "tests/test_billing.py:41: AssertionError", "=========================== short test summary info ============================",
                "FAILED tests/test_billing.py::test_invoice_total - assert 19.97 == 19.98", "1 failed, 11 passed in 0.84s"])),
        ]
        if let dir = ProcessInfo.processInfo.environment["DEVER_TEST_LOG_DIR"] {
            for file in (try? FileManager.default.contentsOfDirectory(atPath: dir).sorted()) ?? [] where file.hasPrefix("tail") {
                if let data = FileManager.default.contents(atPath: dir + "/" + file) { cases.append(("real:" + file, true, "real job", nil, data)) }
            }
        }
        var shown = 0, silent = 0
        for (name, states, job, step, data) in cases {
            guard let excerpt = PipelineLog.excerpt(PipelineLog.lines(data, cut: name.hasPrefix("real"))) else { print("why \(name): no error marker in the tail"); continue }
            let gate = PipelineLog.statesAnError(excerpt)
            print("why \(name): expected \(states ? "states" : "does not say"), code gate \(gate ? "asks the model" : "does not ask"), command \(excerpt.command?.prefix(60) ?? "-"), \(excerpt.output.count) lines, errors \(excerpt.errors)")
            guard gate else { continue }
            for run in 1...3 {
                let start = Date()
                let raw = try? await Intelligence.shared.perform(.onScreen) { model -> FailureAnswer in
                    let room = TextBudget.room(contextSize: model.contextSize, instructions: await model.tokenCount(FailureExplanation.instructions), reserve: 250)
                    let prompt = await FailureExplanation.prompt(job: job, step: step, excerpt: excerpt, room: min(room, 1_600), cost: model.tokenCount) ?? ""
                    return try await model.explainFailure(instructions: FailureExplanation.instructions, prompt: prompt)
                }
                let sentence = raw.flatMap { FailureExplanation.sentence(from: $0, excerpt: excerpt) }
                if sentence == nil { silent += 1 } else { shown += 1 }
                print("why \(name) run \(run) \(String(format: "%.1f", Date().timeIntervalSince(start))) s: stated \(raw.map { "\($0.stated)" } ?? "refused") | line: \(raw?.line.prefix(110) ?? "") | sentence: \(raw?.sentence ?? "") | SHOWN: \(sentence ?? "The log does not say why.")")
            }
        }
        print("why: \(shown) sentences shown, \(silent) times silent")
    }
}
