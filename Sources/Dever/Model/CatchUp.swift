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
        You help \(input.reader) catch up on a team chat channel. The messages are numbered.
        Answer with exactly two lines and nothing else:
        YOU: one short sentence on what is asked of \(input.reader) or awaits their answer, then the number of that message in brackets, like [4]. Count a request that speaks of \(input.reader) without naming them. Write NONE when nothing is asked of them.
        REST: one or two short sentences on what else was said or decided. After each sentence, the number of the message it rests on, in brackets.
        Write the sentences in \(input.language). Say "you" for \(input.reader). Use only what the messages say.
        """
    }

    static func prompt(_ input: Input) -> String {
        input.lines.enumerated().map { "[\($0.offset + 1)] \($0.element.author): \($0.element.text)" }.joined(separator: "\n")
    }

    /// The model's two lines as sentences tied to their messages. Nil when the answer does not
    /// have the shape asked for: nothing is shown rather than something approximate.
    static func parse(_ answer: String, lines: [Line]) -> GeneratedText? {
        var you: String?, rest: String?
        for raw in answer.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let body = body(of: line, label: "YOU:") { you = body }
            else if let body = body(of: line, label: "REST:") { rest = body }
            else if rest != nil, !line.isEmpty { rest! += " " + line }
        }
        guard you != nil || rest != nil else { return nil }
        var sentences: [GeneratedText.Sentence] = []
        if let you, you.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) != "NONE",
           let first = pieces(you, lines: lines).first {
            sentences.append(.init(text: first.text, source: first.source, forYou: true))
        }
        if let rest {
            sentences += pieces(rest, lines: lines).prefix(3).map { .init(text: $0.text, source: $0.source) }
        }
        let text = GeneratedText(sentences: sentences)
        return text.isEmpty ? nil : text
    }

    private static func body(of line: String, label: String) -> String? {
        guard line.uppercased().hasPrefix(label) else { return nil }
        return String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
    }

    /// Cuts "A sentence. [2] Another one [5]." at its bracketed numbers: each piece of text with
    /// the message its number names, or with none when the number is missing or out of range.
    private static func pieces(_ text: String, lines: [Line]) -> [(text: String, source: String?)] {
        let reference = try! NSRegularExpression(pattern: #"\[(\d+)\]"#)
        let whole = text as NSString
        var out: [(String, String?)] = []
        var start = 0
        func add(upTo end: Int, source: String?) {
            let trim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".;,"))
            var piece = whole.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: trim)
            guard piece.count > 2 else {
                // "[2][3]" or "[2]." : a number with no text of its own.
                return
            }
            if let last = piece.last, !"!?…".contains(last) { piece += "." }
            out.append((piece, source))
        }
        for match in reference.matches(in: text, range: NSRange(location: 0, length: whole.length)) {
            let number = Int(whole.substring(with: match.range(at: 1))) ?? 0
            add(upTo: match.range.location, source: lines.indices.contains(number - 1) ? lines[number - 1].ts : nil)
            start = match.range.location + match.range.length
        }
        add(upTo: whole.length, source: nil)
        return out.map { (text: $0.0, source: $0.1) }
    }

    /// Asks the model, alone on it and ahead of background work. Throws when the unread messages
    /// do not all fit its context, when it refuses, or when its answer has not the shape asked.
    static func write(_ input: Input, with intelligence: Intelligence = .shared) async throws -> GeneratedText {
        if IntelligenceStatus.snapshotOverride != nil { return sample(input) }
        return try await intelligence.perform(.onScreen) { model in
            let instructions = instructions(input), prompt = prompt(input)
            let room = TextBudget.room(contextSize: model.contextSize, instructions: await model.tokenCount(instructions))
            guard await model.tokenCount(prompt) <= room else { throw IntelligenceError.tooLong }
            let answer = try await model.respond(instructions: instructions, prompt: prompt, maximumTokens: 300)
            guard let text = parse(answer, lines: input.lines) else { throw IntelligenceError.unavailable }
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
