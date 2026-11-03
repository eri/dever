import SwiftUI

/// Slack's message markup ("mrkdwn") turned into styled text: links, mentions, channels,
/// bold, italic, code, emoji shortcodes and HTML entities.
enum SlackMarkup {
    static func render(_ raw: String, users: [String: String]) -> AttributedString {
        var text = decodeEntities(raw)
        // Slack quotes ("&gt; " at a line start) become a bar, as in Slack.
        text = text.replacingOccurrences(of: #"(?m)^(\x{E001}|>) ?"#, with: "▍ ", options: .regularExpression)
        text = replaceTokens(in: text, users: users)
        text = replaceEmoji(in: text)
        // Slack's *bold*, _italic_, ~strike~ map onto Markdown; `code` is the same in both.
        text = text.replacingOccurrences(of: #"(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])"#, with: "**$1**",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w_])_(?!\s)([^_\n]+?)(?<!\s)_(?![\w_])"#, with: "*$1*",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w~])~(?!\s)([^~\n]+?)(?<!\s)~(?![\w~])"#, with: "~~$1~~",
                                         options: .regularExpression)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "\u{E000}")
            .replacingOccurrences(of: "&gt;", with: "\u{E001}")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `<https://…|label>`, `<https://…>`, `<@U123>`, `<#C123|name>`, `<!here>`.
    private static func replaceTokens(in s: String, users: [String: String]) -> String {
        let pattern = try! NSRegularExpression(pattern: "<([^>|]+)(?:\\|([^>]+))?>")
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in pattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += escape(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            let target = ns.substring(with: m.range(at: 1))
            let label = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : nil
            switch target.first {
            case "@":
                let id = String(target.dropFirst())
                out += "**@\(users[id] ?? label ?? id)**"
            case "#":
                // Without a name the ID means nothing to a reader.
                out += "**#\(label ?? "channel")**"
            case "!":
                out += "**@\(label ?? String(target.dropFirst()))**"
            default:
                out += "[\(escape(label ?? shortURL(target)))](\(target))"
            }
            last = m.range.location + m.range.length
        }
        out += escape(ns.substring(from: last))
        return out.replacingOccurrences(of: "\u{E000}", with: "<").replacingOccurrences(of: "\u{E001}", with: ">")
    }

    /// Long URLs shown by host and the start of their path.
    private static func shortURL(_ url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return url }
        let path = u.path.count > 24 ? String(u.path.prefix(24)) + "…" : u.path
        return host.replacingOccurrences(of: "www.", with: "") + path
    }

    /// Characters Markdown would read as syntax in plain text.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    private static func replaceEmoji(in s: String) -> String {
        let pattern = try! NSRegularExpression(pattern: ":([a-z0-9_+\\-]+):")
        let ns = s as NSString
        var out = s
        for m in pattern.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let name = ns.substring(with: m.range(at: 1))
            // Unknown or custom emoji are dropped rather than left as ":code:" noise.
            let replacement = emoji[name] ?? ""
            out = (out as NSString).replacingCharacters(in: m.range, with: replacement)
        }
        return out.replacingOccurrences(of: "  ", with: " ")
    }

    private static let emoji: [String: String] = [
        "pray": "🙏", "white_check_mark": "✅", "heavy_check_mark": "✔️", "x": "❌", "warning": "⚠️",
        "repeat": "🔁", "relaxed": "☺️", "smile": "😄", "slightly_smiling_face": "🙂", "grinning": "😀",
        "joy": "😂", "sweat_smile": "😅", "wink": "😉", "thinking_face": "🤔", "eyes": "👀", "fire": "🔥",
        "rocket": "🚀", "tada": "🎉", "clap": "👏", "raised_hands": "🙌", "+1": "👍", "thumbsup": "👍",
        "-1": "👎", "ok_hand": "👌", "muscle": "💪", "heart": "❤️", "sparkles": "✨", "bulb": "💡",
        "point_right": "👉", "point_up": "☝️", "memo": "📝", "calendar": "📅", "date": "📅", "link": "🔗",
        "bug": "🐛", "construction": "🚧", "hourglass": "⌛", "hourglass_flowing_sand": "⏳", "star": "⭐",
        "information_source": "ℹ️", "info": "ℹ️", "info2": "ℹ️", "question": "❓", "exclamation": "❗",
        "red_circle": "🔴", "large_green_circle": "🟢", "large_yellow_circle": "🟡", "arrow_right": "➡️",
        "wave": "👋", "sob": "😭", "upside_down_face": "🙃", "chart_with_upwards_trend": "📈",
        "lock": "🔒", "gift": "🎁", "money_with_wings": "💸", "dart": "🎯", "zap": "⚡", "boom": "💥",
    ]
}

/// The channel's latest messages read like Slack: oldest at the top, newest at the bottom,
/// consecutive messages from one person grouped under one name and avatar.
struct SlackThreadView: View {
    let messages: [SlackMessage]       // newest first, as the API returns them
    let users: [String: String]
    let domain: String?
    let channelID: String?
    var limit = 8

    private var shown: [SlackMessage] { Array(messages.prefix(limit).reversed()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, m in
                let previous = index > 0 ? shown[index - 1] : nil
                let grouped = previous.map { $0.user == m.user && m.date.timeIntervalSince($0.date) < 600 } ?? false
                MessageRow(message: m, author: name(m), users: users, grouped: grouped, permalink: permalink(m))
                    .padding(.top, grouped ? 2 : (index == 0 ? 0 : 14))
            }
        }
    }

    private func name(_ m: SlackMessage) -> String {
        m.user.flatMap { users[$0] } ?? "App"
    }

    private func permalink(_ m: SlackMessage) -> URL? {
        guard let domain, let channelID else { return nil }
        return URL(string: "https://\(domain).slack.com/archives/\(channelID)/p\(m.ts.replacingOccurrences(of: ".", with: ""))")
    }
}

private struct MessageRow: View {
    let message: SlackMessage
    let author: String
    let users: [String: String]
    let grouped: Bool
    let permalink: URL?
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if grouped {
                    Text(message.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10)).foregroundStyle(Soot.muted)
                        .opacity(hovering ? 1 : 0)
                } else {
                    Text(String(author.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.75))
                        .frame(width: 32, height: 32)
                        .background(PersonTint.color(for: author), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(width: 32, alignment: .center)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if !grouped {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(author).font(.system(size: 14, weight: .bold)).foregroundStyle(Soot.ink)
                        Text(message.date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 12)).foregroundStyle(Soot.muted)
                    }
                }
                Text(SlackMarkup.render(message.text ?? "", users: users))
                    .font(.system(size: 14))
                    .foregroundStyle(Soot.ink.opacity(0.92))
                    .tint(Soot.lime)
                    .lineSpacing(3)
                    .lineLimit(expanded ? nil : 4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if (message.text?.count ?? 0) > 240 {
                        Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
                    }
                    if let r = message.reply_count, r > 0 {
                        if let permalink {
                            Link(destination: permalink) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 11))
                                    Text("^[\(r) reply](inflect: true)")
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Soot.lime)
                            .help("Open the thread in Slack")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(hovering ? Soot.ground.opacity(0.6) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}
