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
    private let subject = IntelligenceStore.Subject(feature: .catchUp, id: "channel")
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
        store.drop(.catchUp)
        XCTAssertNil(store.text(subject))
        XCTAssertEqual(store.text(other), text("issue"))
    }

    func testPreferencesDefaultOnAndSourceLanguage() {
        let defaults = UserDefaults(suiteName: "intelligence-tests-\(UUID().uuidString)")!
        XCTAssertTrue(IntelligencePreferences.isOn(.catchUp, defaults: defaults))
        defaults.set(false, forKey: IntelligenceFeature.catchUp.settingKey)
        XCTAssertFalse(IntelligencePreferences.isOn(.catchUp, defaults: defaults))
        let french = "On attend ta réponse sur le front avant midi pour savoir si on livre aujourd'hui."
        XCTAssertEqual(IntelligencePreferences.language(forSummaryOf: french, defaults: defaults), "fr")
        defaults.set("english", forKey: IntelligencePreferences.summaryLanguageKey)
        XCTAssertEqual(IntelligencePreferences.language(forSummaryOf: french, defaults: defaults), "en")
    }
}

final class CatchUpTests: XCTestCase {
    private let users = ["U1": SlackUser(id: "U1", name: "Alex", avatar: nil, isBot: false),
                         "U2": SlackUser(id: "U2", name: "Sam", avatar: nil, isBot: false)]

    /// `count` messages, newest first, with timestamps 1…count.
    private func messages(_ count: Int) -> [SlackMessage] {
        (1...count).reversed().map { SlackMessage(ts: "\($0).000000", user: "U1", text: "La migration casse la facturation, message \($0)") }
    }

    private func input(_ messages: [SlackMessage], lastRead: String?, hasEarlier: Bool = false) -> CatchUp.Input? {
        CatchUp.input(messages: messages, lastRead: lastRead, hasEarlier: hasEarlier, users: users, me: "U2",
                      languageCode: { Intelligence.language(of: $0) ?? "en" })
    }

    func testNothingBelowTheThreshold() {
        XCTAssertNil(input(messages(8), lastRead: "3.000000"), "five unread")
        XCTAssertNotNil(input(messages(8), lastRead: "2.000000"), "six unread")
    }

    func testNothingWithoutAReadCursor() {
        XCTAssertNil(input(messages(12), lastRead: nil))
    }

    func testOnlyTheUnreadOldestFirstWithNamesAndLanguage() throws {
        let input = try XCTUnwrap(input(messages(10), lastRead: "3.000000"))
        XCTAssertEqual(input.lines.map(\.ts), (4...10).map { "\($0).000000" })
        XCTAssertEqual(input.lines.first?.author, "Alex")
        XCTAssertEqual(input.reader, "Sam")
        XCTAssertEqual(input.language, "French")
    }

    func testNothingWhenUnreadMessagesAreOlderThanWhatIsLoaded() {
        XCTAssertNil(input(messages(10), lastRead: "0.500000", hasEarlier: true))
        XCTAssertNotNil(input(messages(10), lastRead: "0.500000", hasEarlier: false))
        XCTAssertNotNil(input(messages(10), lastRead: "1.000000", hasEarlier: true))
    }

    func testSystemAndEmptyMessagesDoNotCount() {
        var list = messages(7)
        list[0].subtype = "channel_topic"
        list[1].text = ""
        XCTAssertNil(input(list, lastRead: "0.500000"))
    }

    func testANewMessageIsANewVersion() throws {
        let a = try XCTUnwrap(input(messages(8), lastRead: "1.000000"))
        let b = try XCTUnwrap(input(messages(9), lastRead: "1.000000"))
        XCTAssertNotEqual(a.version, b.version)
    }

    func testLongMessagesAreCut() throws {
        var list = messages(7)
        list[0].text = String(repeating: "log ", count: 1_000)
        let input = try XCTUnwrap(input(list, lastRead: "0.500000"))
        XCTAssertEqual(input.lines.last?.text.count, CatchUp.messageLimit)
    }

    func testPromptNumbersTheMessages() throws {
        let input = try XCTUnwrap(input(messages(6), lastRead: "0.500000"))
        XCTAssertTrue(CatchUp.prompt(input).hasPrefix("[1] Alex: La migration"))
        XCTAssertTrue(CatchUp.instructions(input).contains("French"))
    }

    private var lines: [CatchUp.Line] { (1...6).map { CatchUp.Line(ts: "\($0)", author: "Alex", text: "m\($0)") } }

    func testParsesBothLinesAndTiesSentencesToMessages() throws {
        let text = try XCTUnwrap(CatchUp.parse("""
        YOU: On attend ta réponse sur le front avant midi [6].
        REST: La migration casse la facturation [1]. L'export CSV sort de la version. [4]
        """, lines: lines))
        XCTAssertEqual(text.sentences, [
            .init(text: "On attend ta réponse sur le front avant midi.", source: "6", forYou: true),
            .init(text: "La migration casse la facturation.", source: "1"),
            .init(text: "L'export CSV sort de la version.", source: "4"),
        ])
    }

    func testNoneMeansNoLineForYou() throws {
        let text = try XCTUnwrap(CatchUp.parse("YOU: NONE\nREST: The export leaves the release [2].", lines: lines))
        XCTAssertEqual(text.sentences, [.init(text: "The export leaves the release.", source: "2")])
    }

    func testANumberOutOfRangeLeavesTheSentenceUntied() throws {
        let text = try XCTUnwrap(CatchUp.parse("YOU: none.\nREST: Billing is broken [42]. Nobody told the client", lines: lines))
        XCTAssertEqual(text.sentences, [.init(text: "Billing is broken."), .init(text: "Nobody told the client.")])
    }

    func testAnAnswerWithoutTheShapeIsSilence() {
        XCTAssertNil(CatchUp.parse("Here is a summary of the conversation: lots happened.", lines: lines))
        XCTAssertNil(CatchUp.parse("YOU: NONE\nREST:", lines: lines))
    }

    func testTooLongForTheContextIsRefusedBeforeAsking() async {
        let model = FakeModel()
        model.contextSize = 500
        let long = (1...6).map { CatchUp.Line(ts: "\($0)", author: "Alex", text: String(repeating: "mot ", count: 150)) }
        do {
            _ = try await CatchUp.write(.init(lines: long, reader: "Sam", language: "French"), with: Intelligence(model: model))
            XCTFail("expected a throw")
        } catch { XCTAssertEqual(error as? IntelligenceError, .tooLong) }
        XCTAssertTrue(model.order.isEmpty)
    }
}
