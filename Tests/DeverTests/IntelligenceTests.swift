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
