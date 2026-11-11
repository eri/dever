import Foundation

// A reply drafted in the thread composer (docs/on-device-ai.md, 5.4): one click writes a reply in
// the field from the thread alone, in its language and its tone. It stays a draft until the user
// sends it; nothing leaves before Return.

enum ReplyDraft {
    /// Characters kept of one message of the thread.
    static let messageLimit = 500
    /// Longest draft put in the field: past it the model is rambling, and nothing is proposed.
    static let longest = 400

    struct Line: Equatable, Sendable {
        let author: String
        let text: String
    }

    struct Input: Equatable, Sendable {
        /// The thread, oldest first: its parent, then its replies.
        let lines: [Line]
        /// The user's name as the others write it.
        let reader: String
        /// English name of the language of the thread ("French").
        let language: String
    }

    /// The input for a thread, or nil when there is nothing to answer: no text, or a thread whose
    /// last word is the user's own.
    static func input(parent: SlackMessage, replies: [SlackMessage], users: [String: SlackUser], me: String?) -> Input? {
        let thread = [parent] + replies.filter { $0.ts != parent.ts }
        guard let last = thread.last, last.user != me || me == nil else { return nil }
        let lines: [Line] = thread.compactMap { m in
            let text = SlackPlain.text(m.text ?? "", users: users)
                .replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
            guard !m.isSystem, !text.isEmpty else { return nil }
            return Line(author: m.user.flatMap { users[$0]?.name } ?? "Someone", text: String(text.prefix(messageLimit)))
        }
        guard !lines.isEmpty else { return nil }
        let code = Intelligence.language(of: lines.map(\.text).joined(separator: "\n")) ?? "en"
        let language = Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? "English"
        return Input(lines: lines, reader: me.flatMap { users[$0]?.name } ?? "the reader", language: language)
    }

    static func instructions(_ input: Input) -> String {
        """
        You write the reply \(input.reader) could send in a thread of a team chat. \(input.reader) will read it, change it and send it themselves.
        Write as \(input.reader), in the first person, in \(input.language), in the tone the others use in the thread. One or two short sentences. No greeting, no signature, no emoji, and never \(input.reader)'s own name.
        Answer the last message that expects something of \(input.reader), or the question the thread is about.
        Commit \(input.reader) to nothing the thread does not already say: no date, no deadline, no fact, no decision of their own. When they are asked to do or check something, say that they will look at it and come back.
        """
    }

    static func prompt(_ lines: [Line]) -> String {
        lines.map { "\($0.author): \($0.text)" }.joined(separator: "\n")
    }

    /// The model's reply as put in the field, or nil when it is not one: empty, a speech, or
    /// signed with a name.
    static func text(from answer: String, reader: String) -> String? {
        var text = answer.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // "Sam: I'll look at it" — the model answers in the format of the thread it was given.
        if let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) <= 30,
           MessageSummary.names(String(text[..<colon]), reader: reader) {
            text = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«» "))
        guard text.count > 1, text.count <= longest else { return nil }
        return text
    }

    /// Asks the model, ahead of background work: the user clicked and waits. The parent and the
    /// newest replies that fit are read.
    static func write(_ input: Input, with intelligence: Intelligence = .shared) async throws -> String {
        if IntelligenceStatus.snapshotOverride != nil { return sample }
        return try await intelligence.perform(.onScreen) { model in
            let instructions = instructions(input)
            let room = TextBudget.room(contextSize: model.contextSize, instructions: await model.tokenCount(instructions), reserve: 200)
            var costs: [Int] = []
            for line in input.lines { costs.append(await model.tokenCount("\(line.author): \(line.text)\n")) }
            guard let kept = TextBudget.newestThatFit(input.lines, costs: costs, room: room, required: 1) else {
                MessageSummary.log.notice("reply draft: silent, the thread's first message does not fit")
                throw IntelligenceError.tooLong
            }
            do {
                let answer = try await model.replyDraft(instructions: instructions, prompt: prompt(kept))
                guard let text = text(from: answer, reader: input.reader) else {
                    MessageSummary.log.notice("reply draft: silent, nothing usable in \(answer.count) characters")
                    throw IntelligenceError.unavailable
                }
                MessageSummary.log.notice("reply draft: written from \(kept.count) of \(input.lines.count) messages, \(text.count) characters")
                return text
            } catch {
                MessageSummary.log.error("reply draft: silent, the model failed: \(String(String(describing: error).prefix(160)), privacy: .public)")
                throw error
            }
        }
    }

    /// What a composer calls to get a draft for its thread, or nil when no draft is offered: the
    /// model is not there, its switch is off, or there is nothing to answer.
    @MainActor
    static func offer(parent: SlackMessage, replies: [SlackMessage], users: [String: SlackUser], me: String?) -> (() async -> String?)? {
        guard IntelligenceStatus.shared.offers(.draftReply),
              let input = input(parent: parent, replies: replies, users: users, me: me) else { return nil }
        return { try? await write(input) }
    }

    /// A made-up draft for captures (`DEVER_SNAPSHOT_INTELLIGENCE`).
    static let sample = "I'll look at the front end this morning and come back to you."
}
