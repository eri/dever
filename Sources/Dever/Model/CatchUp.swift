import Foundation
import os

// The Slack catch-up (docs/on-device-ai.md, 5.1): above the unread messages of the rail, one line
// on what is asked of the reader when something is, then a sentence or two on the rest. Written
// by the Mac's model from the unread messages only, each sentence tied to the message it rests on.

enum CatchUp {
    /// Why a catch-up was or was not written: counts and reasons only, never a message's words.
    static let log = Logger(subsystem: "io.github.eri.dever", category: "intelligence")

    /// Unread messages from which a catch-up is written. Below it, reading them is faster.
    static let threshold = 6
    /// Characters kept of one message: a pasted log must not push the others out of the context.
    static let messageLimit = 600

    struct Line: Equatable, Sendable {
        let ts: String
        let author: String
        let text: String
        /// The message names the reader, with an @ or without. Read from the text, not asked of
        /// the model: only such a message can put a line "for you" in the catch-up.
        var namesReader = false
    }

    /// Everything the model is given, and what tells one input from the next.
    struct Input: Equatable, Sendable {
        let lines: [Line]
        /// The reader's name as the others write it.
        let reader: String
        /// English name of the language to write in ("French").
        let language: String
        /// Unread messages older than `lines` exist and are not loaded: the catch-up says what it
        /// covers instead of passing for one of everything.
        var olderUnread = false
        var version: String { "\(lines.first?.ts ?? "")-\(lines.last?.ts ?? "")-\(lines.count)-\(language)-\(olderUnread)" }
    }

    /// The input for a channel, or nil when there is no catch-up to write: no read cursor, or
    /// fewer unread messages than the threshold. `messages` is newest first. When unread messages
    /// reach further back than what is loaded, the input says so (`olderUnread`).
    /// `firstUnread` is the oldest unread message the Overview counted, when it knows: with it, a
    /// page whose every loaded message is unread can still tell that nothing older is.
    static func input(messages: [SlackMessage], lastRead: String?, hasEarlier: Bool, firstUnread: String? = nil,
                      users: [String: SlackUser], me: String?, languageCode: (String) -> String) -> Input? {
        let reader = me.flatMap { users[$0]?.name } ?? ""
        guard let lastRead, let oldest = messages.last else {
            log.notice("catch-up: none, no read cursor or no message (\(messages.count) loaded)")
            return nil
        }
        let reachesTheCursor = SlackTS.isAtOrBefore(oldest.ts, lastRead)
            || (firstUnread.map { SlackTS.isAtOrBefore(oldest.ts, $0) } ?? false)
        let olderUnread = hasEarlier && !reachesTheCursor
        let lines: [Line] = messages.reversed().compactMap { m in
            guard !SlackTS.isAtOrBefore(m.ts, lastRead), !m.isSystem else { return nil }
            let text = SlackPlain.text(m.text ?? "", users: users)
            guard !text.isEmpty else { return nil }
            return Line(ts: m.ts, author: m.user.flatMap { users[$0]?.name } ?? "Someone",
                        text: String(text.prefix(messageLimit)),
                        namesReader: me.map { (m.text ?? "").contains("<@\($0)") } ?? false || names(text, reader: reader))
        }
        guard lines.count >= threshold else {
            log.notice("catch-up: none, \(lines.count) unread of \(messages.count) loaded, under \(threshold)")
            return nil
        }
        let code = languageCode(lines.map(\.text).joined(separator: "\n"))
        let language = Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? "English"
        return Input(lines: lines, reader: reader.isEmpty ? "the reader" : reader, language: language,
                     olderUnread: olderUnread)
    }

    /// Fewest messages worth a catch-up when the context cannot hold them all.
    static let fewestKept = 3

    /// What the block says under its sentences when it does not cover every unread message.
    static func coverage(kept: Int) -> String { "Covers the last \(kept) unread messages" }

    static func instructions(_ input: Input) -> String {
        """
        You help \(input.reader) catch up on a team chat channel they have not read. The messages are numbered. \(input.reader) is the reader.
        List what \(input.reader) has to do, if anything, then the one or two most important other things that were said or decided. Do not repeat what \(input.reader) has to do in the rest.
        Something is asked of \(input.reader) when a message tells or asks them to do, check, review or answer something. That includes a message written to someone else that says \(input.reader) should, must or could do it ("\(input.reader) should look at it", "il faudrait que \(input.reader) regarde"), with or without an @. A piece of news, a decision or a reminder to all is not a request. One action per request, the most pressing first, two at most. Write each as a to-do item that starts with a verb in the infinitive ("Vérifier le front avant midi", "Review the pull request"): never a question, never "you" or "vous".
        Every sentence you write is in \(input.language), whatever language the messages are in: translate when they differ. Short plain sentences in your own words, never a quotation of a message: say what happened, not what a message contains. Each sentence names what it is about, so that it is understood without the messages. Never name \(input.reader). Use only what the messages say.
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
        // An action stands only on a message that names the reader.
        let mine = answer.asked.filter { lines.indices.contains($0.message - 1) && lines[$0.message - 1].namesReader }
        for action in mine.prefix(2) {
            guard let text = tidy(action.sentence, action: true), !sentences.contains(where: { $0.text == text }) else { continue }
            sentences.append(.init(text: text, source: source(action.message), forYou: true))
        }
        for point in answer.rest.prefix(2) {
            guard let text = tidy(point.sentence), !sentences.contains(where: { $0.text == text }) else { continue }
            sentences.append(.init(text: text, source: source(point.message)))
        }
        return sentences.isEmpty ? nil : GeneratedText(sentences: sentences)
    }

    /// `text` holds a word of the reader's name ("Sam" for "Sam Rivers"), as a whole word, whatever
    /// the case and the accents. Words of one or two letters do not count.
    static func names(_ text: String, reader: String) -> Bool {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 })
        }
        return !words(text).isDisjoint(with: words(reader))
    }

    /// A sentence as it is shown: trimmed, a capital first, closed by a full stop. An action is a
    /// to-do item: no closing punctuation, and a question mark the model left is dropped.
    private static func tidy(_ raw: String, action: Bool = false) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // The model sometimes copies a message in quotes and leaves its number behind: `…XP", 2.`
        text = text.replacingOccurrences(of: #"["”’']?,?\s*\[?\d{1,2}\]?\.?$"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”‘’' "))
        if action { text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .?!\u{202F}\u{00A0}")) }
        guard text.count > 2 else { return nil }
        text = text.prefix(1).uppercased() + text.dropFirst()
        if !action, let last = text.last, !".!?…".contains(last) { text += "." }
        return text
    }

    /// Asks the model, alone on it and ahead of background work. When the unread messages do not
    /// all fit its context, the newest that do are read and the text says what it covers. Throws
    /// when too few fit, when the model refuses, or when its answer holds nothing to show.
    static func write(_ input: Input, with intelligence: Intelligence = .shared) async throws -> GeneratedText {
        if IntelligenceStatus.snapshotOverride != nil { return sample(input) }
        return try await intelligence.perform(.onScreen) { model in
            let instructions = instructions(input)
            let room = TextBudget.room(contextSize: model.contextSize, instructions: await model.tokenCount(instructions))
            var costs: [Int] = []
            for (index, line) in input.lines.enumerated() {
                // The number can only grow once older lines are dropped: count with the largest.
                costs.append(await model.tokenCount("[\(index + 1)] \(line.author): \(line.text)\n"))
            }
            guard let kept = TextBudget.newestThatFit(input.lines, costs: costs, room: room), kept.count >= fewestKept else {
                log.notice("catch-up: silent, \(input.lines.count) messages are \(costs.reduce(0, +)) tokens for \(room) of room")
                throw IntelligenceError.tooLong
            }
            let read = Input(lines: kept, reader: input.reader, language: input.language)
            do {
                let answer = try await model.catchUp(instructions: instructions, prompt: prompt(read))
                guard var text = text(from: answer, lines: kept) else {
                    log.notice("catch-up: silent, the answer held nothing to show")
                    throw IntelligenceError.unavailable
                }
                if input.olderUnread || kept.count < input.lines.count { text.note = coverage(kept: kept.count) }
                log.notice("catch-up: written from \(kept.count) of \(input.lines.count) messages, \(text.sentences.count) sentences, older unread \(input.olderUnread)")
                return text
            } catch {
                log.error("catch-up: silent, the model failed: \(String(String(describing: error).prefix(160)), privacy: .public)")
                throw error
            }
        }
    }

    /// A made-up catch-up for captures (`DEVER_SNAPSHOT_INTELLIGENCE`), tied to real messages.
    static func sample(_ input: Input) -> GeneratedText {
        GeneratedText(sentences: [
            .init(text: "Answer on the front end before noon", source: input.lines.last?.ts, forYou: true),
            .init(text: "The migration breaks billing for older accounts.", source: input.lines.first?.ts),
            .init(text: "The CSV export leaves this release."),
        ], note: input.olderUnread ? coverage(kept: input.lines.count) : nil)
    }
}
