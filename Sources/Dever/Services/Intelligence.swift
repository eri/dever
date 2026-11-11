import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

// The Mac's own language model (Apple Intelligence, the Foundation Models framework), and the
// only file that imports it. Rules and decisions: docs/on-device-ai.md. The app runs on macOS 14;
// everything here answers "unsupported" where the framework or the model does not exist, and the
// rest of the app only ever sees `IntelligenceAvailability` and plain strings.

/// Whether the system model can be used right now, in the app's own words.
enum IntelligenceAvailability: String, Equatable, Sendable {
    /// Ready to generate.
    case available
    /// The Mac can run it but the model is not there: still downloading, or held back by the
    /// system (Siri's language and the Mac's differ, say). The API does not say which.
    case notReady
    /// Apple Intelligence is switched off in System Settings.
    case off
    /// macOS before 26, or a Mac that can never run it. Nothing to show, nothing to fix.
    case unsupported

    /// The user can do something about it in System Settings.
    var fixable: Bool { self == .off || self == .notReady }
}

/// What the system model is asked, behind a protocol so tests and snapshots run without it.
protocol LanguageModel: Sendable {
    var availability: IntelligenceAvailability { get }
    /// Tokens one session holds, instructions and answer included; 0 when unknown.
    var contextSize: Int { get }
    /// Tokens `text` costs. An estimate where the system cannot count.
    func tokenCount(_ text: String) async -> Int
    /// One answer to one prompt, in a fresh session. Throws on refusal, guardrail, overflow.
    func respond(instructions: String, prompt: String, maximumTokens: Int?) async throws -> String
    /// A catch-up of numbered messages, in the shape the model is held to (guided generation):
    /// free text in two labelled lines came back mislabelled or translated one time in two.
    func catchUp(instructions: String, prompt: String) async throws -> CatchUpAnswer
    /// One message shortened: what kind of message it is, and its point in a sentence.
    func summarise(instructions: String, prompt: String) async throws -> MessageSummaryAnswer
}

/// What the model says of one message.
struct MessageSummaryAnswer: Equatable, Sendable {
    /// One of `MessageSummary.kinds`: what the message expects of its readers.
    var kind: String
    var summary: String
}

/// What the model says of a run of numbered messages.
struct CatchUpAnswer: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        var sentence: String
        /// Number of the message it rests on, from 1; anything else ties it to none.
        var message: Int
    }
    /// What the model reads as asked of the reader, one item per request, and where. It lists a
    /// reminder to all as readily as a request to one: `CatchUp` keeps only the items whose
    /// message names the reader.
    var asked: [Point]
    var rest: [Point]
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct CatchUpPoint {
    @Guide(description: "One short sentence") var sentence: String
    @Guide(description: "Number of the message the sentence rests on") var message: Int
}

@available(macOS 26.0, *)
@Generable
private struct MessageSummaryShape {
    @Guide(description: "The point of the message in one full sentence of at most 20 words, understandable by someone who has not read the channel: who or what it is about, and what is asked, wrong, decided or announced")
    var summary: String
    @Guide(description: "Request: the author asks someone to do, send, check, fix or decide something. Question: the author asks for an answer or an opinion. Problem: something is wrong, slow, failing, late or to fix, and no one in particular is asked. Update: only when nothing is asked and nothing is wrong, such as progress, news, a decision, a welcome",
           .anyOf(["Request", "Question", "Problem", "Update"]))
    var kind: String
}

@available(macOS 26.0, *)
@Generable
private struct CatchUpShape {
    @Guide(description: "The reader's to-do list: one item per thing a message asks of them, each a short action that starts with a verb in the infinitive, never a question. Empty when no message asks anything of the reader", .maximumCount(2))
    var actions: [CatchUpPoint]
    @Guide(description: "The most important other things said or decided, the most important first: each a full sentence in your own words that names what it is about. No quotation, no message number inside the sentence", .count(1...2))
    var rest: [CatchUpPoint]
}
#endif

enum IntelligenceError: Error, Equatable {
    case unavailable
    /// The input does not fit the model's context; the caller shows nothing (rule 4).
    case tooLong
}

/// The system model. Every member checks the OS and the framework itself.
struct SystemLanguageModelClient: LanguageModel {
    var availability: IntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.appleIntelligenceNotEnabled): return .off
            case .unavailable(.modelNotReady): return .notReady
            case .unavailable(.deviceNotEligible): return .unsupported
            case .unavailable: return .notReady
            }
        }
        #endif
        return .unsupported
    }

    var contextSize: Int {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return SystemLanguageModel.default.contextSize }
        #endif
        return 0
    }

    func tokenCount(_ text: String) async -> Int {
        #if canImport(FoundationModels)
        if #available(macOS 26.4, *), let n = try? await SystemLanguageModel.default.tokenCount(for: text) {
            return n
        }
        #endif
        return TextBudget.estimate(text)
    }

    func respond(instructions: String, prompt: String, maximumTokens: Int?) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else { throw IntelligenceError.unavailable }
            let session = LanguageModelSession(instructions: instructions)
            let options = GenerationOptions(maximumResponseTokens: maximumTokens)
            return try await session.respond(to: prompt, options: options).content
        }
        #endif
        throw IntelligenceError.unavailable
    }

    func catchUp(instructions: String, prompt: String) async throws -> CatchUpAnswer {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else { throw IntelligenceError.unavailable }
            let session = LanguageModelSession(instructions: instructions)
            let shape = try await session.respond(to: prompt, generating: CatchUpShape.self,
                                                  options: GenerationOptions(maximumResponseTokens: 300)).content
            let asked = shape.actions.map { CatchUpAnswer.Point(sentence: $0.sentence, message: $0.message) }
            return CatchUpAnswer(asked: asked, rest: shape.rest.map { .init(sentence: $0.sentence, message: $0.message) })
        }
        #endif
        throw IntelligenceError.unavailable
    }

    func summarise(instructions: String, prompt: String) async throws -> MessageSummaryAnswer {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else { throw IntelligenceError.unavailable }
            let session = LanguageModelSession(instructions: instructions)
            let shape = try await session.respond(to: prompt, generating: MessageSummaryShape.self,
                                                  options: GenerationOptions(maximumResponseTokens: 100)).content
            return MessageSummaryAnswer(kind: shape.kind, summary: shape.summary)
        }
        #endif
        throw IntelligenceError.unavailable
    }

    /// Calls `change` once, the next time the system's availability moves; the caller re-arms.
    static func onAvailabilityChange(_ change: @escaping @Sendable () -> Void) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            withObservationTracking { _ = SystemLanguageModel.default.availability } onChange: { change() }
        }
        #endif
    }
}

/// The one door to the model: one generation at a time (the framework refuses concurrent
/// requests, and the chip is shared with the system), what is on screen before what is not.
actor Intelligence {
    static let shared = Intelligence(model: SystemLanguageModelClient())

    enum Priority: Int, Sendable { case background, onScreen }

    let model: LanguageModel
    private var busy = false
    private var waiting: [(priority: Priority, resume: CheckedContinuation<Void, Never>)] = []

    init(model: LanguageModel) { self.model = model }

    /// Runs `work` alone on the model, after anything of higher priority already waiting.
    func perform<T: Sendable>(_ priority: Priority,
                              _ work: @Sendable (LanguageModel) async throws -> T) async throws -> T {
        guard model.availability == .available else { throw IntelligenceError.unavailable }
        await acquire(priority)
        defer { release() }
        return try await work(model)
    }

    private func acquire(_ priority: Priority) async {
        guard busy else { busy = true; return }
        await withCheckedContinuation { waiting.append((priority, $0)) }
    }

    private func release() {
        // On screen first; among equals, the oldest.
        if let next = waiting.firstIndex(where: { $0.priority == .onScreen }) ?? waiting.indices.first {
            waiting.remove(at: next).resume.resume()
        } else {
            busy = false
        }
    }

    /// The language most of `text` is written in ("fr", "en"), or nil when it cannot tell.
    nonisolated static func language(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(4_000)))
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }
}

/// What fits in the model's context. The window is small (docs/on-device-ai.md, section 2), so
/// every feature says what it keeps when its input is too long, and this does the counting.
enum TextBudget {
    /// Tokens kept free for the answer.
    static let answerReserve = 400

    /// Tokens for `text` when the system cannot count: French and English run near four
    /// characters a token; three keeps a margin.
    static func estimate(_ text: String) -> Int { (text.count + 2) / 3 }

    /// Tokens left for the input once the instructions and the answer have their room.
    static func room(contextSize: Int, instructions: Int, reserve: Int = answerReserve) -> Int {
        max(0, contextSize - instructions - reserve)
    }

    /// The newest items that fit `room`, in their original order. `costs` is parallel to `items`,
    /// oldest first. `required` leading items (a thread's parent, an issue's description) are
    /// always kept; nil when they alone do not fit.
    static func newestThatFit<T>(_ items: [T], costs: [Int], room: Int, required: Int = 0) -> [T]? {
        precondition(items.count == costs.count)
        let head = min(required, items.count)
        var left = room - costs.prefix(head).reduce(0, +)
        guard left >= 0 else { return nil }
        var start = items.count
        while start > head, costs[start - 1] <= left {
            left -= costs[start - 1]
            start -= 1
        }
        return Array(items.prefix(head)) + Array(items[start...])
    }
}
