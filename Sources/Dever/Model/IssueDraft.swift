import Foundation

// A Linear issue from a Slack message (docs/on-device-ai.md, 5.3): the sheet opens at once with
// the message as its description, and the Mac's model, when it is there, proposes a title, a
// shorter description and a priority. Nothing is created before the user says so.

enum IssueDraft {
    /// Longest title kept; Linear shows about that much in a list.
    static let longestTitle = 90

    struct Input: Equatable, Sendable {
        let author: String
        /// The message in plain text.
        let text: String
        /// English name of the language to write in ("English").
        let language: String
    }

    struct Fields: Equatable, Sendable {
        var title: String
        var description: String
        /// Linear's 0–4: none, urgent, high, medium, low.
        var priority: Int
    }

    /// What the sheet holds before the model has answered, and all it holds without a model: the
    /// message's own words as the description, the title left to the user.
    static func plain(_ input: Input) -> Fields {
        Fields(title: "", description: input.text, priority: 0)
    }

    static func instructions(_ input: Input) -> String {
        """
        You turn one message from a team chat into an entry for an issue tracker.
        Write in \(input.language), whatever language the message is in.
        The title is the work to do, as an action that starts with a verb, ten words at most, with no final period and without the author's name.
        The description says, in two or three short sentences, what is wrong or wanted, where, and what was observed. Keep names of screens, numbers and identifiers exactly as written.
        Use only what the message says. Do not make a statement stronger than the message does, and do not propose a solution the message does not give.
        The priority is none unless the message itself says how urgent or how blocking it is.
        """
    }

    /// The model's answer as the sheet shows it, or nil when it has no usable title.
    static func fields(from answer: IssueDraftAnswer, input: Input) -> Fields? {
        var title = answer.title.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .\"“”*`"))
        guard title.count > 2 else { return nil }
        if title.count > longestTitle { title = String(title.prefix(longestTitle)).trimmingCharacters(in: .whitespaces) }
        title = title.prefix(1).uppercased() + title.dropFirst()
        let description = answer.description.trimmingCharacters(in: .whitespacesAndNewlines)
        // The model reads "to fix before the release" as urgent. A priority is kept only when the
        // message has a word for it; otherwise it is the user's to set.
        return Fields(title: title, description: description.isEmpty ? input.text : description,
                      priority: saysHowUrgent(input.text) ? priority(answer.priority) : 0)
    }

    /// The message itself says how urgent or blocking it is, in English or in French.
    static func saysHowUrgent(_ text: String) -> Bool {
        let folded = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        return ["urgent", "asap", "blocking", "blocker", "blocked", "bloquant", "bloque", "critical", "critique",
                "high priority", "low priority", "prioritaire", "showstopper"].contains { folded.contains($0) }
    }

    /// The model's word for a priority as Linear's number; anything unknown is no priority.
    static func priority(_ word: String) -> Int {
        switch word.lowercased() {
        case "urgent": 1
        case "high": 2
        case "medium": 3
        case "low": 4
        default: 0
        }
    }

    /// The description as it is sent to Linear: the user's text, then where it came from.
    static func description(_ text: String, author: String, permalink: URL?) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let permalink else { return body }
        let source = "From [\(author)'s message in Slack](\(permalink.absoluteString))"
        return body.isEmpty ? source : body + "\n\n" + source
    }

    /// Asks the model, ahead of background work: the sheet is on screen and waits for it.
    static func write(_ input: Input, with intelligence: Intelligence = .shared) async throws -> Fields {
        if IntelligenceStatus.snapshotOverride != nil { return sample }
        return try await intelligence.perform(.onScreen) { model in
            let instructions = instructions(input)
            let room = TextBudget.room(contextSize: model.contextSize, instructions: await model.tokenCount(instructions), reserve: 300)
            var prompt = "\(input.author): \(input.text)"
            let tokens = await model.tokenCount(prompt)
            if tokens > room, tokens > 0 { prompt = String(prompt.prefix(prompt.count * room / tokens * 9 / 10)) }
            do {
                let answer = try await model.issueDraft(instructions: instructions, prompt: prompt)
                guard let fields = fields(from: answer, input: input) else {
                    MessageSummary.log.notice("issue draft: silent, no usable title")
                    throw IntelligenceError.unavailable
                }
                MessageSummary.log.notice("issue draft: written, title of \(fields.title.count) characters, priority \(fields.priority)")
                return fields
            } catch {
                MessageSummary.log.error("issue draft: silent, the model failed: \(String(String(describing: error).prefix(160)), privacy: .public)")
                throw error
            }
        }
    }

    /// A made-up draft for captures (`DEVER_SNAPSHOT_INTELLIGENCE`).
    static let sample = Fields(title: "Refresh the tips list after a language change",
                               description: "After the language is changed, the tips list still shows the tips of the previous language, and learners open them. Seen on the preview, in the web extension.",
                               priority: 2)
}
