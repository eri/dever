import Foundation

// The Slack catch-up (docs/on-device-ai.md, 5.1): above the unread messages of the rail, one line
// on what is asked of the reader when something is, then a sentence or two on the rest. Written
// by the Mac's model from the unread messages only, each sentence tied to the message it rests on.

enum CatchUp {
    /// Unread messages from which a catch-up is written. Below it, reading them is faster.
    static let threshold = 6
    /// Characters kept of one message: a pasted log must not push the others out of the context.
    static let messageLimit = 600

    struct Line: Equatable, Sendable {
        let ts: String
        let author: String
        let text: String
    }

    /// Everything the model is given, and what tells one input from the next.
    struct Input: Equatable, Sendable {
        let lines: [Line]
        /// The reader's name as the others write it.
        let reader: String
        /// English name of the language to write in ("French").
        let language: String
        var version: String { "\(lines.first?.ts ?? "")-\(lines.last?.ts ?? "")-\(lines.count)-\(language)" }
    }

    /// The input for a channel, or nil when there is no catch-up to write: no read cursor, fewer
    /// unread messages than the threshold, or unread messages older than what is loaded (a
    /// catch-up of a part would pass for one of the whole). `messages` is newest first.
    static func input(messages: [SlackMessage], lastRead: String?, hasEarlier: Bool,
                      users: [String: SlackUser], me: String?, languageCode: (String) -> String) -> Input? {
        guard let lastRead, let oldest = messages.last else { return nil }
        if hasEarlier, !SlackTS.isAtOrBefore(oldest.ts, lastRead) { return nil }
        let lines: [Line] = messages.reversed().compactMap { m in
            guard !SlackTS.isAtOrBefore(m.ts, lastRead), !m.isSystem else { return nil }
            let text = SlackPlain.text(m.text ?? "", users: users)
            guard !text.isEmpty else { return nil }
            return Line(ts: m.ts, author: m.user.flatMap { users[$0]?.name } ?? "Someone",
                        text: String(text.prefix(messageLimit)))
        }
        guard lines.count >= threshold else { return nil }
        let code = languageCode(lines.map(\.text).joined(separator: "\n"))
        let language = Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? "English"
        return Input(lines: lines, reader: me.flatMap { users[$0]?.name } ?? "the reader", language: language)
    }

    static func instructions(_ input: Input) -> String {
        """
        You help \(input.reader) catch up on a team chat channel they have not read. The messages are numbered. \(input.reader) is the reader.
        Say what is asked of \(input.reader), if anything, then the one or two most important other things that were said or decided. Do not repeat what is asked of \(input.reader) in the rest.
        Something is asked of \(input.reader) when a message tells or asks them to do, check, review or answer something. That includes a message written to someone else that says \(input.reader) should, must or could do it ("\(input.reader) should look at it", "il faudrait que \(input.reader) regarde"), with or without an @. When several messages ask, keep the latest.
        Every sentence you write is in \(input.language), whatever language the messages are in: translate when they differ. Short plain sentences in your own words, not copies of the messages. Speak to \(input.reader) directly: "you" (in French "tu", never "vous"), never their name. Use only what the messages say.
        """
    }

    static func prompt(_ input: Input) -> String {
        input.lines.enumerated().map { "[\($0.offset + 1)] \($0.element.author): \($0.element.text)" }.joined(separator: "\n")
    }

    /// The model's answer as sentences tied to their messages: the line for the reader first,
    /// then the rest. A number that names no message leaves its sentence untied; a sentence said
    /// twice is kept once. Nil when nothing is left to show.
    static func text(from answer: CatchUpAnswer, lines: [Line]) -> GeneratedText? {
        func source(_ number: Int) -> String? { lines.indices.contains(number - 1) ? lines[number - 1].ts : nil }
        var sentences: [GeneratedText.Sentence] = []
        if let asked = answer.asked, let text = tidy(asked.sentence) {
            sentences.append(.init(text: text, source: source(asked.message), forYou: true))
        }
        for point in answer.rest.prefix(2) {
            guard let text = tidy(point.sentence), !sentences.contains(where: { $0.text == text }) else { continue }
            sentences.append(.init(text: text, source: source(point.message)))
        }
        return sentences.isEmpty ? nil : GeneratedText(sentences: sentences)
    }

    /// A sentence as it is shown: trimmed, a capital first, closed by a full stop.
    private static func tidy(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 2 else { return nil }
        text = text.prefix(1).uppercased() + text.dropFirst()
        if let last = text.last, !".!?…".contains(last) { text += "." }
        return text
    }

    /// Asks the model, alone on it and ahead of background work. Throws when the unread messages
    /// do not all fit its context, when it refuses, or when its answer holds nothing to show.
    static func write(_ input: Input, with intelligence: Intelligence = .shared) async throws -> GeneratedText {
        if IntelligenceStatus.snapshotOverride != nil { return sample(input) }
        return try await intelligence.perform(.onScreen) { model in
            let instructions = instructions(input), prompt = prompt(input)
            let room = TextBudget.room(contextSize: model.contextSize, instructions: await model.tokenCount(instructions))
            guard await model.tokenCount(prompt) <= room else { throw IntelligenceError.tooLong }
            let answer = try await model.catchUp(instructions: instructions, prompt: prompt)
            guard let text = text(from: answer, lines: input.lines) else { throw IntelligenceError.unavailable }
            return text
        }
    }

    /// A made-up catch-up for captures (`DEVER_SNAPSHOT_INTELLIGENCE`), tied to real messages.
    static func sample(_ input: Input) -> GeneratedText {
        GeneratedText(sentences: [
            .init(text: "Your answer on the front end is awaited before noon.", source: input.lines.last?.ts, forYou: true),
            .init(text: "The migration breaks billing for older accounts.", source: input.lines.first?.ts),
            .init(text: "The CSV export leaves this release."),
        ])
    }
}
