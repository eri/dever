import Foundation

// A long Slack message shown as its summary in the rail (docs/on-device-ai.md, 5.7). The rail
// already cuts a long message at four lines; the summary takes the place of that cut, the
// original stays one click away, and the room always shows the messages themselves.

enum MessageSummary {
    /// Same test as the rail's "Show more": only a message the rail would cut is summarised.
    static let minimumLength = 240
    /// Longest summary worth showing, as a share of the original: past it, the original reads as fast.
    static let longestShare = 0.7
    /// And in characters: a summary is two lines of the rail, three at most, whatever the message.
    static let longest = 180

    struct Input: Equatable, Sendable {
        let author: String
        let text: String
        /// English name of the language to write in ("French").
        let language: String
        /// An edited message is another input.
        var version: String { "\(language)-\(text.count)-\(text.hashValue)" }
    }

    static func isLong(_ message: SlackMessage) -> Bool {
        (message.text?.count ?? 0) > minimumLength && !message.isSystem
    }

    static func subject(channel: String, ts: String) -> IntelligenceStore.Subject {
        .init(feature: .messageSummary, id: "\(channel)/\(ts)")
    }

    /// The input for a message, or nil when it is not one the rail cuts.
    static func input(_ message: SlackMessage, users: [String: SlackUser], languageCode: (String) -> String) -> Input? {
        guard isLong(message) else { return nil }
        // Slack's marks for bold and code are noise to the model, and it copies them out.
        let text = SlackPlain.text(message.text ?? "", users: users)
            .replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
        guard text.count > minimumLength else { return nil }
        let language = Locale(identifier: "en_US").localizedString(forLanguageCode: languageCode(text)) ?? "English"
        return Input(author: message.user.flatMap { users[$0]?.name } ?? "Someone", text: text, language: language)
    }

    /// The kinds a message can be, as shown at the head of its summary.
    static let kinds = ["Request", "Warning", "Decision", "Info"]

    static func instructions(_ input: Input) -> String {
        """
        You shorten one message from a team chat for someone who has not read the channel.
        Give its point in one full sentence of at most 20 words, in \(input.language) whatever language the message is in, then say what kind of message it is. The sentence must stand on its own: name who or what it is about (the feature, the ticket, the person), then what is asked, wrong, decided or announced.
        Do not list what the message lists: give the outcome. Keep names, numbers and ticket identifiers exactly as written. Use only what the message says, and do not make a statement stronger than the message does. No greeting, no opinion, no "this message", no formatting marks.
        The kind: Request when the author asks someone to do, send, check, answer or decide something; Warning when the author reports a bug, a failure, a delay or a risk; Decision only when the author states a choice already made; Info for the rest. A message that asks the team to decide is a Request, not a Decision.
        """
    }

    /// The model's answer as shown, or nil when it is not worth the place of the original:
    /// empty, too long for two lines, or nearly as long as the message.
    static func text(from answer: MessageSummaryAnswer, original: String) -> GeneratedText? {
        var plain = answer.summary.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // "Request: get the screenshots": the kind has its own place at the head of the block.
        for kind in kinds where plain.lowercased().hasPrefix(kind.lowercased() + ":") {
            plain = String(plain.dropFirst(kind.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        // Whole sentences only, as many as fit: a summary cut mid-sentence reads as a broken one.
        var summary = ""
        plain.enumerateSubstrings(in: plain.startIndex..., options: .bySentences) { sentence, _, _, stop in
            guard let sentence else { return }
            if summary.count + sentence.count > longest + 1 { stop = true } else { summary += sentence }
        }
        summary = summary.trimmingCharacters(in: .whitespaces)
        guard summary.count > 2, Double(summary.count) <= Double(original.count) * longestShare else { return nil }
        summary = summary.prefix(1).uppercased() + summary.dropFirst()
        var kind = kinds.first { $0.lowercased() == answer.kind.lowercased() }
        // "We should decide whether…" asks for a decision; the model files it under Decision.
        if kind == "Decision", summary.range(of: #"\b(decide|décider|should|whether)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            kind = "Request"
        }
        return GeneratedText(sentences: [.init(text: summary)], kind: kind)
    }

    /// Asks the model, behind anything on screen that waits for it. A message longer than the
    /// context is read from its start, as far as fits.
    static func write(_ input: Input, with intelligence: Intelligence = .shared) async throws -> GeneratedText {
        if IntelligenceStatus.snapshotOverride != nil { return sample }
        return try await intelligence.perform(.background) { model in
            let instructions = instructions(input)
            let room = TextBudget.room(contextSize: model.contextSize, instructions: await model.tokenCount(instructions), reserve: 200)
            var prompt = "\(input.author): \(input.text)"
            let tokens = await model.tokenCount(prompt)
            if tokens > room, tokens > 0 {
                prompt = String(prompt.prefix(prompt.count * room / tokens * 9 / 10))
            }
            do {
                let answer = try await model.summarise(instructions: instructions, prompt: prompt)
                guard let text = text(from: answer, original: input.text) else {
                    CatchUp.log.notice("message summary: silent, nothing shorter than the \(input.text.count) characters of the message")
                    throw IntelligenceError.unavailable
                }
                CatchUp.log.notice("message summary: written, \(input.text.count) characters to \(text.sentences.first?.text.count ?? 0)")
                return text
            } catch {
                CatchUp.log.error("message summary: silent, the model failed: \(String(String(describing: error).prefix(160)), privacy: .public)")
                throw error
            }
        }
    }

    /// A made-up summary for captures (`DEVER_SNAPSHOT_INTELLIGENCE`).
    static let sample = GeneratedText(sentences: [
        .init(text: "The final QA report of AI Tips passes 21 of 24 criteria; SUP-931 is to fix before the release.")
    ], kind: "Warning")
}
