import Foundation

// An unread message that speaks of the reader by name without a Slack mention
// (docs/on-device-ai.md, 5.2). Found in code, with no model: the model cannot be trusted to say
// who a message is about. Stricter than `MessageSummary.names`, because a hit here becomes a
// "for you" item of the Overview rather than an arrow on a summary already on screen.

enum DetectedMention {
    /// English and French words that are also given names. Written without a capital they are
    /// the word ("it will break", "max 3 retries"); they count only as the rules of `names` say.
    static let commonWords: Set<String> = [
        "will", "mark", "rose", "max", "art", "bill", "june", "may", "april", "august", "grace", "hope",
        "joy", "faith", "rich", "frank", "jack", "rob", "pat", "sue", "dot", "don", "ray", "guy", "dean",
        "page", "penny", "olive", "prince", "pierre", "marin", "ange", "aime", "noel", "eden", "iris",
        "jean", "blanche", "aurore", "clement", "constant", "fidele", "juste", "parfait", "modeste",
    ]

    private static func fold(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }

    private static func nameWords(_ name: String) -> Set<String> {
        Set(fold(name).split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 2 })
    }

    /// The words that point at the reader alone: those of their name, of three letters or more,
    /// that no other person of the workspace carries. Two people called Sam: "Sam" names neither.
    static func words(reader me: String, users: [String: SlackUser]) -> Set<String> {
        guard let mine = users[me]?.name else { return [] }
        var words = nameWords(mine)
        for (id, user) in users where id != me && !user.isBot && !words.isEmpty {
            words.subtract(nameWords(user.name))
        }
        return words
    }

    /// The message's own prose: no mention of anyone, no channel, no link, no code. A name in a
    /// branch, a URL or a command is not someone speaking of the reader.
    static func prose(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: #"```[\s\S]*?```"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`[^`\n]*`"#, with: " ", options: .regularExpression)
        // <https://…|label> keeps its label when the label is not itself an address.
        s = s.replacingOccurrences(of: #"<(?:https?|mailto):[^>|]*\|(?![a-z]+:)([^>]*)>"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\S+@\S+|\bhttps?://\S+"#, with: " ", options: .regularExpression)
        return s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `raw` (Slack markup) speaks of the reader: its prose holds one of `words` as a whole word,
    /// whatever the case and the accents. A word that is also a common word counts only with its
    /// capital, and at the head of a sentence only when it is called out ("Will, can you…"):
    /// "Will you merge?" and "Mark this as done" name no one.
    static func names(_ raw: String, words: Set<String>) -> Bool {
        guard !words.isEmpty else { return false }
        let text = prose(raw)
        var found = false
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { word, range, _, stop in
            guard let word, words.contains(fold(word)) else { return }
            if commonWords.contains(fold(word)) {
                guard word.first?.isUppercase == true else { return }
                // Any word has its capital at the head of a sentence or of a line.
                let before = text[..<range.lowerBound]
                let previous = before.last { !$0.isWhitespace }
                let heads = previous.map { ".!?:;".contains($0) } ?? true || before.last?.isNewline == true
                let calledOut = text[range.upperBound...].first.map { ",:".contains($0) } ?? false
                if heads, !calledOut { return }
            }
            found = true
            stop = true
        }
        return found
    }

    /// The unread messages that speak of the reader without a mention, newest first. A message
    /// that carries a real mention of them is never here: it is already among the mentions.
    static func find(in unread: [SlackMessage], me: String, users: [String: SlackUser]) -> [ProjectSnapshot.SlackStats.Mention] {
        let words = words(reader: me, users: users)
        guard !words.isEmpty else { return [] }
        return unread
            .filter { m in
                let text = m.text ?? ""
                return m.user != me && !text.contains("<@\(me)>") && !text.contains("<@\(me)|") && names(text, words: words)
            }
            .sorted { $0.ts > $1.ts }
            .map { m in
                .init(ts: m.ts, author: m.user.flatMap { users[$0]?.name } ?? "Someone",
                      text: SlackPlain.text(m.text ?? "", users: users), date: m.date)
            }
    }
}
