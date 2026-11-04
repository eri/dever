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

    static let emoji: [String: String] = [
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

/// Block Kit `rich_text` turned into styled text. It is the faithful source: `text` loses
/// list markers, code blocks and quote structure, which readers need.
enum SlackRichText {
    /// Nil when the message carries no rich text block, so the caller falls back to `text`.
    static func render(_ blocks: [SlackBlock]?, users: [String: SlackUser]) -> AttributedString? {
        let rich = (blocks ?? []).filter { $0.type == "rich_text" }
        guard !rich.isEmpty else { return nil }
        var out = AttributedString()
        for block in rich {
            for element in block.elements ?? [] { append(element, to: &out, users: users) }
        }
        while out.characters.last?.isNewline == true { out.removeSubrange(out.index(beforeCharacter: out.endIndex)..<out.endIndex) }
        return out.characters.isEmpty ? nil : out
    }

    private static func append(_ e: SlackRichElement, to out: inout AttributedString, users: [String: SlackUser]) {
        func startBlock() {
            if !out.characters.isEmpty, out.characters.last?.isNewline != true { out.append(AttributedString("\n")) }
        }
        switch e.type {
        case "rich_text_section":
            for leaf in e.elements ?? [] { out.append(render(leaf, users: users)) }
        case "rich_text_list":
            startBlock()
            let ordered = e.listStyle == "ordered"
            let indent = String(repeating: "    ", count: e.indent ?? 0)
            for (n, item) in (e.elements ?? []).enumerated() {
                if n > 0 { out.append(AttributedString("\n")) }
                var marker = AttributedString(indent + (ordered ? "\(n + 1).  " : "•  "))
                marker.foregroundColor = .secondary
                out.append(marker)
                for leaf in item.elements ?? [] { out.append(render(leaf, users: users)) }
            }
        case "rich_text_quote":
            startBlock()
            var quoted = AttributedString()
            for leaf in e.elements ?? [] { quoted.append(render(leaf, users: users)) }
            let lines = String(quoted.characters).split(separator: "\n", omittingEmptySubsequences: false)
            for (i, line) in lines.enumerated() {
                if i > 0 { out.append(AttributedString("\n")) }
                var bar = AttributedString("▍ "); bar.foregroundColor = .secondary
                out.append(bar)
                out.append(AttributedString(String(line)))
            }
        case "rich_text_preformatted":
            startBlock()
            var code = AttributedString()
            for leaf in e.elements ?? [] { code.append(render(leaf, users: users)) }
            code.inlinePresentationIntent = .code
            out.append(code)
        default:
            for leaf in e.elements ?? [] { out.append(render(leaf, users: users)) }
        }
    }

    private static func render(_ leaf: SlackRichElement, users: [String: SlackUser]) -> AttributedString {
        var s: AttributedString
        switch leaf.type {
        case "text": s = AttributedString(leaf.text ?? "")
        case "link":
            s = AttributedString(leaf.text ?? leaf.url.map(shortURL) ?? "")
            if let url = leaf.url.flatMap(URL.init(string:)) { s.link = url }
        case "user":
            s = AttributedString("@" + (leaf.user_id.flatMap { users[$0]?.name } ?? leaf.user_id ?? "user"))
            s.inlinePresentationIntent = .stronglyEmphasized
        case "channel":
            s = AttributedString("#" + (leaf.name ?? "channel"))
            s.inlinePresentationIntent = .stronglyEmphasized
        case "broadcast":
            s = AttributedString("@" + (leaf.range ?? "here"))
            s.inlinePresentationIntent = .stronglyEmphasized
        case "emoji":
            s = AttributedString(leaf.unicode.flatMap(emoji) ?? leaf.name.flatMap { SlackMarkup.emoji[$0] } ?? "")
        default:
            s = AttributedString(leaf.text ?? "")
        }
        if let style = leaf.style {
            var intent: InlinePresentationIntent = s.inlinePresentationIntent ?? []
            if style.bold == true { intent.insert(.stronglyEmphasized) }
            if style.italic == true { intent.insert(.emphasized) }
            if style.strike == true { intent.insert(.strikethrough) }
            if style.code == true { intent.insert(.code) }
            if !intent.isEmpty { s.inlinePresentationIntent = intent }
        }
        return s
    }

    /// "1f44d-1f3fb" → 👍🏻
    private static func emoji(_ codes: String) -> String? {
        let scalars = codes.split(separator: "-").compactMap { UInt32($0, radix: 16).flatMap(Unicode.Scalar.init) }
        return scalars.isEmpty ? nil : String(String.UnicodeScalarView(scalars))
    }

    static func shortURL(_ url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return url }
        let path = u.path.count > 24 ? String(u.path.prefix(24)) + "…" : u.path
        return host.replacingOccurrences(of: "www.", with: "") + path
    }
}

/// The channel's latest messages read like Slack: oldest at the top, newest at the bottom,
/// consecutive messages from one person grouped under one name and avatar. Threads open in
/// place; "Show earlier" walks back through the channel's history.
struct SlackThreadView: View {
    let messages: [SlackMessage]       // newest first, as the API returns them
    let users: [String: SlackUser]
    let domain: String?
    let channelID: String?
    var shown = 8
    var hasEarlier = false
    var loadingEarlier = false
    var showEarlier: () -> Void = {}
    var replies: (SlackMessage) async throws -> [SlackMessage] = { _ in [] }

    private var visible: [SlackMessage] { Array(messages.prefix(shown).reversed()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasEarlier || messages.count > shown {
                if loadingEarlier {
                    WaitingLine().padding(.horizontal, 8).padding(.bottom, 12)
                        .accessibilityElement().accessibilityLabel("Loading earlier messages")
                } else {
                    Button("Show earlier", action: showEarlier)
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.lime)
                        .padding(.horizontal, 8).padding(.bottom, 12)
                        .modifier(FocusOutline(radius: 4))
                }
            }
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, m in
                let previous = index > 0 ? visible[index - 1] : nil
                let grouped = previous.map { $0.user == m.user && m.date.timeIntervalSince($0.date) < 600 } ?? false
                MessageRow(message: m, user: m.user.flatMap { users[$0] }, users: users, grouped: grouped,
                           permalink: permalink(m), replies: replies)
                    .padding(.top, grouped ? 2 : (index == 0 ? 0 : 14))
            }
        }
    }

    private func permalink(_ m: SlackMessage) -> URL? {
        guard let domain, let channelID else { return nil }
        return URL(string: "https://\(domain).slack.com/archives/\(channelID)/p\(m.ts.replacingOccurrences(of: ".", with: ""))")
    }
}

/// A person's picture from Slack, or their initial on a tint until it is there.
struct SlackAvatar: View {
    var user: SlackUser?
    var name: String
    var size: CGFloat = 32
    var radius: CGFloat = 8
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PersonTint.color(for: name))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .accessibilityHidden(true)
        .task(id: user?.avatar) {
            guard let user else { image = nil; return }
            image = await SlackMediaCache.shared.avatar(for: user, pixels: Int(size * 2.5))
        }
    }
}

private struct MessageRow: View {
    @EnvironmentObject var app: AppState
    let message: SlackMessage
    let user: SlackUser?
    let users: [String: SlackUser]
    let grouped: Bool
    let permalink: URL?
    let replies: (SlackMessage) async throws -> [SlackMessage]
    @State private var expanded = false
    @State private var hovering = false
    @State private var threadOpen = false
    @State private var thread: [SlackMessage]?
    @State private var threadFailed = false

    private var author: String { user?.name ?? "App" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if grouped {
                    Text(message.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10)).foregroundStyle(Soot.muted)
                        .opacity(hovering ? 1 : 0)
                } else {
                    SlackAvatar(user: user, name: author)
                }
            }
            .frame(width: 32, alignment: .center)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if !grouped {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(author).font(.system(size: 14, weight: .bold)).foregroundStyle(Soot.ink)
                        Text(message.date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 12)).foregroundStyle(Soot.muted)
                    }
                }
                MessageBody(message: message, users: users, expanded: $expanded)
                MessageExtras(message: message)
                HStack(spacing: 12) {
                    if (message.text?.count ?? 0) > 240 {
                        Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
                    }
                    if let r = message.reply_count, r > 0 {
                        Button {
                            threadOpen.toggle()
                            if threadOpen, thread == nil { Task { await loadThread() } }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: threadOpen ? "chevron.down" : "bubble.left.and.bubble.right").font(.system(size: 11))
                                Text("^[\(r) reply](inflect: true)")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Soot.lime)
                        .modifier(FocusOutline(radius: 4))
                        .accessibilityLabel(threadOpen ? "Hide replies" : "Show \(r) replies")
                        if let permalink {
                            Link(destination: permalink) {
                                HStack(spacing: 3) { Text("Open in Slack"); Image(systemName: "arrow.up.right") }
                            }
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
                            .help("Open the thread in Slack")
                        }
                    }
                }
                if threadOpen {
                    ThreadReplies(replies: thread, failed: threadFailed, users: users)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(hovering ? Soot.ground.opacity(0.6) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private func loadThread() async {
        threadFailed = false
        do { thread = try await replies(message) } catch { threadFailed = true }
    }
}

/// The text of a message: rich text when Slack sent blocks, mrkdwn otherwise.
private struct MessageBody: View {
    let message: SlackMessage
    let users: [String: SlackUser]
    @Binding var expanded: Bool

    var body: some View {
        let text = SlackRichText.render(message.blocks, users: users)
            ?? SlackMarkup.render(message.text ?? "", users: users.mapValues(\.name))
        if !text.characters.isEmpty {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Soot.ink.opacity(0.92))
                .tint(Soot.lime)
                .lineSpacing(3)
                .lineLimit(expanded ? nil : 4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What a message carries besides its text: pictures, files, link previews.
private struct MessageExtras: View {
    let message: SlackMessage

    var body: some View {
        let files = message.files ?? []
        let cards = (message.attachments ?? []).filter { !$0.isEmpty }
        if !files.isEmpty || !cards.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(files) { file in
                    if file.isReadable, file.isImage { SlackImage(file: file) } else { FileRow(file: file) }
                }
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in LinkPreview(card: card) }
            }
            .padding(.top, 2)
        }
    }
}

/// A picture shared in the channel, at Slack's 360px thumbnail, scaled to the column.
private struct SlackImage: View {
    @EnvironmentObject var app: AppState
    let file: SlackFile
    @State private var image: CGImage?
    @State private var failed = false

    private var ratio: CGFloat {
        let w = CGFloat(file.thumb_360_w ?? file.original_w ?? 4), h = CGFloat(file.thumb_360_h ?? file.original_h ?? 3)
        return max(0.4, min(3, w / max(h, 1)))
    }

    var body: some View {
        let width = min(320, CGFloat(file.thumb_360_w ?? 320))
        Group {
            if let image {
                Link(destination: URL(string: file.permalink ?? "") ?? URL(string: "https://slack.com")!) {
                    Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                }
                .buttonStyle(.plain)
                .help("Open \(file.displayName) in Slack")
            } else if failed {
                FileRow(file: file)
            } else {
                Skeleton(radius: 8).frame(width: width, height: width / ratio)
            }
        }
        .frame(maxWidth: width, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.line))
        .accessibilityLabel(Text(file.displayName))
        .accessibilityAddTraits(.isImage)
        .task(id: file.id) {
            guard let url = (file.thumb_360 ?? file.thumb_480).flatMap(URL.init(string:)) else { failed = true; return }
            image = try? await app.withSlack { client in
                await SlackMediaCache.shared.thumbnail(url, fileID: file.id, variant: "360", maxPixels: 720, client: client)
            }
            if image == nil { failed = true }
        }
    }
}

/// A compact row for a file: kind, name, size. Opens the file in Slack.
private struct FileRow: View {
    let file: SlackFile

    private var symbol: String {
        if !file.isReadable { return "lock" }
        let type = (file.filetype ?? "").lowercased(), mime = file.mimetype ?? ""
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if type == "pdf" { return "doc.richtext" }
        if ["zip", "gzip", "tar", "rar"].contains(type) { return "doc.zipper" }
        if ["xlsx", "xls", "csv", "gsheet", "numbers"].contains(type) { return "tablecells" }
        if ["pptx", "ppt", "gslides", "keynote"].contains(type) { return "rectangle.on.rectangle" }
        if ["swift", "js", "ts", "py", "rb", "go", "java", "json", "yaml", "html", "css", "sh"].contains(type) {
            return "chevron.left.forwardslash.chevron.right"
        }
        return "doc"
    }

    private var detail: String {
        if !file.isReadable { return "In Slack" }
        var parts: [String] = []
        if let t = file.filetype, !t.isEmpty { parts.append(t.uppercased()) }
        if let size = file.size, size > 0 { parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let row = HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Soot.muted).frame(width: 18)
            Text(file.displayName).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
            Spacer(minLength: 8)
            Text(detail).font(.system(size: 11)).foregroundStyle(Soot.muted).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.displayName), \(detail)")
        if let url = file.permalink.flatMap(URL.init(string:)) {
            Link(destination: url) { row }.buttonStyle(.plain).modifier(FocusOutline(radius: 8))
                .help("Open in Slack")
        } else {
            row
        }
    }
}

/// A link unfurl: the site, the title and a line of its text, with a bar in the site's colour.
private struct LinkPreview: View {
    let card: SlackAttachment
    @State private var image: CGImage?

    private var link: URL? { (card.title_link ?? card.from_url ?? card.original_url).flatMap(URL.init(string:)) }
    private var bar: Color { card.color.flatMap(Color.init(hex:)) ?? Soot.line }

    var body: some View {
        let body = HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(bar).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                if let site = card.service_name ?? card.author_name {
                    Text(site).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted).lineLimit(1)
                }
                if let title = card.title ?? card.pretext ?? card.fallback {
                    Text(SlackMarkup.render(title, users: [:])).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Soot.ink).tint(Soot.ink).lineLimit(2)
                }
                if let text = card.text, !text.isEmpty {
                    Text(SlackMarkup.render(text, users: [:])).font(.system(size: 12)).foregroundStyle(Soot.ink.opacity(0.8))
                        .tint(Soot.lime).lineLimit(3)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let image {
                Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(8)
        .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .task(id: card.thumb_url ?? card.image_url) {
            guard let url = (card.thumb_url ?? card.image_url).flatMap(URL.init(string:)) else { return }
            image = await SlackMediaCache.shared.publicImage(url, maxPixels: 96)
        }
        if let link {
            Link(destination: link) { body }.buttonStyle(.plain).modifier(FocusOutline(radius: 8))
        } else {
            body
        }
    }
}

/// A thread's replies, under their parent and set off by a line.
private struct ThreadReplies: View {
    let replies: [SlackMessage]?
    let failed: Bool
    let users: [String: SlackUser]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if failed {
                Text("Couldn't load the replies.").font(.system(size: 12)).foregroundStyle(Soot.muted)
            } else if let replies {
                ForEach(replies) { reply in
                    let user = reply.user.flatMap { users[$0] }
                    HStack(alignment: .top, spacing: 8) {
                        SlackAvatar(user: user, name: user?.name ?? "App", size: 22, radius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(user?.name ?? "App").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                                Text(reply.date.formatted(.relative(presentation: .named))).font(.system(size: 11)).foregroundStyle(Soot.muted)
                            }
                            MessageBody(message: reply, users: users, expanded: .constant(true))
                            MessageExtras(message: reply)
                        }
                    }
                }
            } else {
                WaitingLine().frame(width: 120).accessibilityElement().accessibilityLabel("Loading replies")
            }
        }
        .padding(.leading, 10)
        .padding(.top, 6)
        .overlay(alignment: .leading) { Rectangle().fill(Soot.line).frame(width: 2).padding(.top, 6) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Replies")
    }
}

private extension Color {
    /// "#36a64f" → a colour; Slack sends attachment colours as hex, with or without the hash.
    init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
