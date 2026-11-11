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

    var answer = CatchUpAnswer(asked: [], rest: [])
    func catchUp(instructions: String, prompt: String) async throws -> CatchUpAnswer {
        lock.withLock { order.append(prompt) }
        return answer
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

    func testUnreadOlderThanWhatIsLoadedIsSaidNotHidden() throws {
        XCTAssertTrue(try XCTUnwrap(input(messages(10), lastRead: "0.500000", hasEarlier: true)).olderUnread)
        XCTAssertFalse(try XCTUnwrap(input(messages(10), lastRead: "0.500000", hasEarlier: false)).olderUnread)
        XCTAssertFalse(try XCTUnwrap(input(messages(10), lastRead: "1.000000", hasEarlier: true)).olderUnread)
    }

    func testEveryLoadedMessageUnreadIsEverythingWhenTheOverviewCountedNoOlderOne() throws {
        func counted(_ firstUnread: String?) throws -> Bool {
            try XCTUnwrap(CatchUp.input(messages: messages(10), lastRead: "0.500000", hasEarlier: true, firstUnread: firstUnread,
                                        users: users, me: "U2", languageCode: { _ in "fr" })).olderUnread
        }
        XCTAssertFalse(try counted("1.000000"), "the oldest unread is the oldest loaded")
        XCTAssertTrue(try counted("0.700000"), "an unread message older than what is loaded")
        XCTAssertTrue(try counted(nil))
    }

    func testAPartialCatchUpSaysWhatItCovers() async throws {
        let model = FakeModel()
        model.answer = .init(asked: [], rest: [.init(sentence: "Billing is broken", message: 1)])
        let text = try await CatchUp.write(.init(lines: lines, reader: "Sam", language: "English", olderUnread: true),
                                           with: Intelligence(model: model))
        XCTAssertEqual(text.note, "Covers the last 6 unread messages")
        let whole = try await CatchUp.write(.init(lines: lines, reader: "Sam", language: "English"), with: Intelligence(model: model))
        XCTAssertNil(whole.note)
    }

    func testOnlyTheNewestThatFitAreReadAndNumberedFromOne() async throws {
        let model = FakeModel()
        // Room for the instructions, the answer and about four of ten 300-character messages.
        model.contextSize = TextBudget.estimate(CatchUp.instructions(.init(lines: [], reader: "Sam", language: "English"))) + TextBudget.answerReserve + 450
        model.answer = .init(asked: [], rest: [.init(sentence: "The newest kept", message: 4), .init(sentence: "The oldest kept", message: 1)])
        let ten = (1...10).map { CatchUp.Line(ts: "\($0)", author: "Alex", text: String(repeating: "mot ", count: 75)) }
        let text = try await CatchUp.write(.init(lines: ten, reader: "Sam", language: "English"), with: Intelligence(model: model))
        XCTAssertEqual(text.sentences.map(\.source), ["10", "7"])
        XCTAssertEqual(text.note, "Covers the last 4 unread messages")
        XCTAssertTrue(model.order.last?.hasPrefix("[1] Alex:") ?? false)
    }

    func testALongMessageIsReadThroughItsSummaryAndTheCatchUpWaitsForIt() throws {
        let list = messages(8)
        func made(_ summary: @escaping (SlackMessage) -> CatchUp.Summary) throws -> CatchUp.Input {
            try XCTUnwrap(CatchUp.input(messages: list, lastRead: "0.500000", hasEarlier: false, users: users, me: "U2",
                                        languageCode: { _ in "fr" }, summary: summary))
        }
        let waiting = try made { $0.ts == "8.000000" ? .pending : .none }
        XCTAssertEqual(waiting.awaiting, 1)
        let written = GeneratedText(sentences: [.init(text: "Le correctif est poussé.")], kind: "Update")
        let ready = try made { $0.ts == "8.000000" ? .ready(written) : .none }
        XCTAssertEqual(ready.awaiting, 0)
        XCTAssertEqual(ready.lines.last?.text, "Update: Le correctif est poussé.")
        XCTAssertNotEqual(waiting.version, ready.version, "the summary landing is a new input")
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

    private var lines: [CatchUp.Line] { (1...6).map { CatchUp.Line(ts: "\($0)", author: "Alex", text: "m\($0)", namesReader: $0 == 6) } }

    func testTheLineForYouComesFirstAndSentencesAreTiedAndTidied() throws {
        let answer = CatchUpAnswer(asked: [.init(sentence: "peux-tu regarder le front ?", message: 6)],
                                   rest: [.init(sentence: "la migration casse la facturation", message: 1),
                                          .init(sentence: "Pas d'export CSV dans cette version.", message: 4)])
        let text = try XCTUnwrap(CatchUp.text(from: answer, lines: lines))
        XCTAssertEqual(text.sentences, [
            .init(text: "Peux-tu regarder le front", source: "6", forYou: true),
            .init(text: "La migration casse la facturation.", source: "1"),
            .init(text: "Pas d'export CSV dans cette version.", source: "4"),
        ])
    }

    func testNothingAskedMeansNoLineForYou() throws {
        let text = try XCTUnwrap(CatchUp.text(from: .init(asked: [], rest: [.init(sentence: "The export leaves the release", message: 2)]), lines: lines))
        XCTAssertEqual(text.sentences, [.init(text: "The export leaves the release.", source: "2")])
    }

    func testANumberOutOfRangeLeavesTheSentenceUntied() throws {
        let text = try XCTUnwrap(CatchUp.text(from: .init(asked: [.init(sentence: "Check the screen", message: 0)],
                                                           rest: [.init(sentence: "Billing is broken", message: 42)]), lines: lines))
        // An action tied to no message cannot be checked against one that names the reader: dropped.
        XCTAssertEqual(text.sentences, [.init(text: "Billing is broken.")])
    }

    func testAnActionStandsOnlyOnAMessageThatNamesTheReader() throws {
        let answer = CatchUpAnswer(asked: [.init(sentence: "Read the sprint notes", message: 3), .init(sentence: "Vérifier le front", message: 6)],
                                   rest: [.init(sentence: "Billing is broken", message: 1)])
        let text = try XCTUnwrap(CatchUp.text(from: answer, lines: lines))
        XCTAssertEqual(text.sentences, [.init(text: "Vérifier le front", source: "6", forYou: true), .init(text: "Billing is broken.", source: "1")])
    }

    func testAMessageNamesTheReaderWithOrWithoutAnAt() throws {
        XCTAssertTrue(CatchUp.names("Il faudrait que sam regarde le front", reader: "Sam Rivers"))
        XCTAssertTrue(CatchUp.names("@Sam Rivers tu peux relire ?", reader: "Sam Rivers"))
        XCTAssertFalse(CatchUp.names("Le même problème qu'hier", reader: "Sam Rivers"))
        XCTAssertFalse(CatchUp.names("samedi on livre", reader: "Sam Rivers"))
        var list = messages(7)
        list[0].text = "<@U2> tu peux relire la PR ?"
        list[1].text = "il faudrait que Sam regarde le front"
        let input = try XCTUnwrap(input(list, lastRead: "0.500000"))
        XCTAssertEqual(input.lines.map(\.namesReader), [false, false, false, false, false, true, true])
    }

    func testAQuotedCopyAndItsLeftoverNumberAreCleaned() throws {
        let answer = CatchUpAnswer(asked: [], rest: [.init(sentence: "“The feature gives +2 XP”, 2.", message: 2),
                                                     .init(sentence: "Testing is complete, covering all 24 criteria\", 6.", message: 6)])
        let text = try XCTUnwrap(CatchUp.text(from: answer, lines: lines))
        XCTAssertEqual(text.sentences.map(\.text), ["The feature gives +2 XP.", "Testing is complete, covering all 24 criteria."])
        let ticket = CatchUpAnswer(asked: [.init(sentence: "Fix SUP-931", message: 6)], rest: [.init(sentence: "The release is on the 12", message: 1)])
        XCTAssertEqual(CatchUp.text(from: ticket, lines: lines)?.sentences.map(\.text), ["Fix SUP-931", "The release is on the 12."])
    }

    func testEmptyAndRepeatedSentencesAreDropped() {
        XCTAssertNil(CatchUp.text(from: .init(asked: [.init(sentence: " ", message: 1)], rest: [.init(sentence: "", message: 2)]), lines: lines))
        let twice = CatchUp.text(from: .init(asked: [], rest: [.init(sentence: "Same thing", message: 1), .init(sentence: "same thing.", message: 2)]), lines: lines)
        XCTAssertEqual(twice?.sentences.count, 1)
    }

    func testWriteAsksTheModelAndTiesItsAnswer() async throws {
        let model = FakeModel()
        model.answer = .init(asked: [.init(sentence: "Answer before noon", message: 6)], rest: [.init(sentence: "Billing is broken", message: 1)])
        let text = try await CatchUp.write(.init(lines: lines, reader: "Sam", language: "English"), with: Intelligence(model: model))
        XCTAssertEqual(text.sentences.map(\.source), ["6", "1"])
        XCTAssertEqual(model.order.count, 1)
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

/// The real model, on a Mac that has it: `DEVER_TEST_REAL_MODEL=1 swift test --filter RealModel`.
/// Skipped everywhere else; it checks the shape of the answer, not its words.
final class RealModelTests: XCTestCase {
    func testCatchUpOfAFrenchChannel() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEVER_TEST_REAL_MODEL"] == "1", "needs the system model")
        let said = [
            ("Alex", "Le déploiement de la preview est cassé depuis hier soir, la page de paiement renvoie une 500."),
            ("Robin", "Confirmé, la migration ne remplit pas plan_id pour les comptes créés avant mars."),
            ("Charlie", "On peut mettre une valeur par défaut legacy en attendant ?"),
            ("Robin", "Oui mais il faut que le front gère legacy, sinon l'écran de facturation plante."),
            ("Charlie", "Ok, décision : pas d'export CSV dans cette version."),
            ("Alex", "Il faudrait que Sam regarde le front avant midi, c'est lui qui a fait l'écran de facturation."),
        ]
        let lines = said.enumerated().map { CatchUp.Line(ts: "\($0.offset + 1)", author: $0.element.0, text: $0.element.1, namesReader: CatchUp.names($0.element.1, reader: "Sam")) }
        let start = Date()
        let text = try await CatchUp.write(.init(lines: lines, reader: "Sam", language: "French"))
        print("catch-up in \(String(format: "%.1f", Date().timeIntervalSince(start))) s:")
        for s in text.sentences { print(s.forYou ? " → " : "   ", s.text, "[\(s.source ?? "-")]") }
        XCTAssertEqual(text.sentences.first?.forYou, true)
        XCTAssertEqual(text.sentences.first?.source, "6")
        XCTAssertLessThanOrEqual(text.sentences.count, 4)
    }

    func testNothingAskedInAnEnglishChannel() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEVER_TEST_REAL_MODEL"] == "1", "needs the system model")
        let said = [
            ("Alex", "The staging deploy is green again."),
            ("Robin", "Nice. I merged the retry fix this morning."),
            ("Charlie", "Docs for the new webhook are up."),
            ("Alex", "Reminder: sprint review moves to Thursday."),
            ("Robin", "Fine for me."),
            ("Charlie", "Same."),
        ]
        let lines = said.enumerated().map { CatchUp.Line(ts: "\($0.offset + 1)", author: $0.element.0, text: $0.element.1, namesReader: CatchUp.names($0.element.1, reader: "Sam")) }
        let text = try await CatchUp.write(.init(lines: lines, reader: "Sam", language: "English"))
        for s in text.sentences { print(s.forYou ? " → " : "   ", s.text, "[\(s.source ?? "-")]") }
        XCTAssertFalse(text.sentences.contains { $0.forYou })
        // An example sentence in the instructions came back as if the channel had said it.
        XCTAssertFalse(text.sentences.contains { $0.text.contains("QA") || $0.text.contains("bugs") })
    }
}

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

extension RealModelTests {
    /// The whole chain as the rail runs it: each long message summarised, then the catch-up
    /// written from the summaries and the short messages.
    func testCatchUpFedByMessageSummaries() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEVER_TEST_REAL_MODEL"] == "1", "needs the system model")
        let said: [(String, String)] = [
            ("Estelle", "Hey team, I have the customer weekly tomorrow at 11am and I'd love to show them what's coming with AI Tips. Could someone send me 2 or 3 screenshots of the feature in the web extension before tomorrow morning? Nothing fancy, the tip page and the success screen would be perfect. Thanks a lot!"),
            ("Marco", "Hi Kyryl, welcome! You can start testing AI tips. FYI: tips are a new kind of content we're pushing on the platform. They are short, hands-on AI tips that learners validate with a 'Nailed it!' button to earn +2 XP. The acceptance criteria are in the Linear project and the preview is deployed on PR-4714. Ping me if anything is unclear."),
            ("Marco", "Tom, Tarik: there is no tip menu on the preview back office."),
            ("Tarik", "Fixed, redeploying."),
            ("Kyryl", "One more thing on sync: when I change a tip in the back office, it takes 1 to 2 minutes before the change shows in the web extension. It is not a bug strictly speaking, the cache is refreshed on a timer, but for editors it feels broken because they do not see their fix. I think we should decide whether we optimize for faster sync before the release or document the delay."),
            ("Kyryl", "Hi team, final QA report for the tips feature (QA-27). Scope: all test cases executed, covering all 24 acceptance criteria. Tested on preview PR-4714 in the web extension and the back office. Result: 21 criteria pass, 3 fail. SUP-931: the tips list isn't refreshed after a language change. SUP-928: visual flickering in the tip content text when toggling the favorite heart. SUP-929: sync latency for backend tip changes. None is blocking for the demo, but SUP-931 should be fixed before the release. Sam, can you take SUP-931?"),
        ]
        var lines: [CatchUp.Line] = []
        for (index, (author, text)) in said.enumerated() {
            var read = text
            if text.count > MessageSummary.minimumLength,
               let summary = try? await MessageSummary.write(.init(author: author, text: text, language: "English")) {
                read = "\(summary.kind ?? "Update"): \(summary.sentences.map(\.text).joined(separator: " "))"
            }
            print("line \(index + 1): \(author) | \(read.prefix(170))")
            lines.append(.init(ts: "\(index + 1)", author: author, text: read, namesReader: CatchUp.names(text, reader: "Sam")))
        }
        let text = try await CatchUp.write(.init(lines: lines, reader: "Sam", language: "English"))
        for s in text.sentences { print(s.forYou ? "CATCH →" : "CATCH  ", s.text, "[\(s.source ?? "-")]") }
        XCTAssertEqual(text.sentences.first?.forYou, true)
        XCTAssertEqual(text.sentences.first?.source, "6")
    }
}
