import SwiftUI

/// Slack's message markup ("mrkdwn") turned into styled text: links, mentions, channels,
/// bold, italic, code, emoji shortcodes and HTML entities.
enum SlackMarkup {
    static func render(_ raw: String, users: [String: String], channels: [String: String] = [:]) -> AttributedString {
        var text = decodeEntities(raw)
        // Slack quotes ("&gt; " at a line start) become a bar, as in Slack.
        text = text.replacingOccurrences(of: #"(?m)^(\x{E001}|>) ?"#, with: "▍ ", options: .regularExpression)
        text = replaceTokens(in: text, users: users, channels: channels)
        text = replaceEmoji(in: text)
        // Slack's *bold*, _italic_, ~strike~ map onto Markdown; `code` is the same in both.
        text = text.replacingOccurrences(of: #"(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])"#, with: "**$1**",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w_])_(?!\s)([^_\n]+?)(?<!\s)_(?![\w_])"#, with: "*$1*",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w~])~(?!\s)([^~\n]+?)(?<!\s)~(?![\w~])"#, with: "~~$1~~",
                                         options: .regularExpression)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var out = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        SlackLinks.styleChips(in: &out)
        return out
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "\u{E000}")
            .replacingOccurrences(of: "&gt;", with: "\u{E001}")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `<https://…|label>`, `<https://…>`, `<@U123>`, `<#C123|name>`, `<!here>`.
    private static func replaceTokens(in s: String, users: [String: String], channels: [String: String]) -> String {
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
                out += "**#\(label ?? channels[String(target.dropFirst())] ?? "channel")**"
            case "!":
                out += "**@\(label ?? String(target.dropFirst()))**"
            default:
                let bare = SlackLinks.isBare(text: label, url: target)
                out += "[\(escape(bare ? SlackLinks.chipLabel(target, channels: channels) : label!))](\(target))"
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
            let replacement = SlackMarkup.unicode(name) ?? ""
            out = (out as NSString).replacingCharacters(in: m.range, with: replacement)
        }
        return out.replacingOccurrences(of: "  ", with: " ")
    }

    /// A Slack short name ("+1", "wave::skin-tone-3") as text, from the full standard table.
    static func unicode(_ name: String) -> String? {
        let parts = name.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        guard let base = parts.first, let scalar = SlackEmojiTable.names[base] ?? emoji[base] else { return nil }
        guard parts.count > 1, let tone = parts.last, tone.hasPrefix("skin-tone-"),
              let n = Int(tone.dropFirst(10)), (2...6).contains(n) else { return scalar }
        let modifiers: [Unicode.Scalar] = ["\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"]
        return scalar.replacingOccurrences(of: "\u{FE0F}", with: "") + String(modifiers[n - 2])
    }

    /// "white_check_mark" → "white check mark", "+1" → "thumbs up": for labels and tooltips.
    static func reactionName(_ name: String) -> String {
        switch name {
        case "+1", "thumbsup": return "thumbs up"
        case "-1": return "thumbs down"
        default:
            return name.split(separator: ":").first.map { $0.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ") } ?? name
        }
    }

    static let emoji: [String: String] = [
        "100": "💯", "partying_face": "🥳", "heart_eyes": "😍", "raised_hand": "✋", "handshake": "🤝",
        "saluting_face": "🫡", "blue_heart": "💙", "green_heart": "💚", "yellow_heart": "💛", "purple_heart": "💜",
        "orange_heart": "🧡", "black_heart": "🖤", "white_heart": "🤍", "star-struck": "🤩", "sunglasses": "😎",
        "grimacing": "😬", "cry": "😢", "confused": "😕", "neutral_face": "😐", "no_entry_sign": "🚫",
        "ballot_box_with_check": "☑️", "heavy_plus_sign": "➕", "pushpin": "📌", "crossed_fingers": "🤞",
        "laughing": "😆", "rolling_on_the_floor_laughing": "🤣", "smiley": "😃", "blush": "😊", "pleading_face": "🥺",
        "face_with_monocle": "🧐", "nerd_face": "🤓", "exploding_head": "🤯", "skull": "💀", "ghost": "👻",
        "robot_face": "🤖", "brain": "🧠", "mag": "🔍", "pencil2": "✏️", "package": "📦", "ship": "🚢",
        "checkered_flag": "🏁", "trophy": "🏆", "medal": "🏅", "first_place_medal": "🥇", "coffee": "☕",
        "beer": "🍺", "beers": "🍻", "pizza": "🍕", "cake": "🍰", "sunny": "☀️", "rainbow": "🌈",
        "hammer_and_wrench": "🛠️", "gear": "⚙️", "wrench": "🔧", "test_tube": "🧪", "art": "🎨",
        "mega": "📣", "loudspeaker": "📢", "bell": "🔔", "alarm_clock": "⏰", "stopwatch": "⏱️",
        "chart_with_downwards_trend": "📉", "bar_chart": "📊", "moneybag": "💰", "dollar": "💵",
        "shrug": "🤷", "man-shrugging": "🤷‍♂️", "woman-shrugging": "🤷‍♀️", "facepalm": "🤦",
        "man-facepalming": "🤦‍♂️", "woman-facepalming": "🤦‍♀️", "raising_hand": "🙋", "ok": "🆗",
        "new": "🆕", "sos": "🆘", "up": "🆙", "cool": "🆒", "free": "🆓", "1234": "🔢", "soon": "🔜",
        "heavy_minus_sign": "➖", "arrow_left": "⬅️", "arrow_up": "⬆️", "arrow_down": "⬇️", "arrows_counterclockwise": "🔄",
        "see_no_evil": "🙈", "hear_no_evil": "🙉", "speak_no_evil": "🙊", "monkey": "🐒", "cat": "🐱", "dog": "🐶",
        "unicorn_face": "🦄", "turtle": "🐢", "snail": "🐌", "bee": "🐝", "butterfly": "🦋", "owl": "🦉",
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

/// The pointing hand over anything clickable that is not a system control.
struct HandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(CursorArea(cursor: .pointingHand))
    }
}

extension View {
    func handCursor() -> some View { modifier(HandCursor()) }
}

extension SlackMessage {
    /// Channel events Slack posts as messages: renames, topics, pins…
    var isSystem: Bool {
        ["channel_name", "channel_purpose", "channel_topic", "pinned_item", "unpinned_item", "bot_add", "bot_remove",
         "channel_archive", "channel_unarchive", "reminder_add", "group_name", "group_purpose", "group_topic"].contains(subtype ?? "")
    }
}

/// Bare URLs read badly in a narrow column. They become a chip: a short label on a lime wash,
/// and a Slack permalink says what it is ("Message in #channel") instead of showing its path.
enum SlackLinks {
    /// Thin spaces mark a chip label, so the style pass finds it after Markdown parsing.
    private static let mark = "\u{2009}"

    static func chipLabel(_ url: String, channels: [String: String]) -> String {
        mark + plainLabel(url, channels: channels) + mark
    }

    static func plainLabel(_ url: String, channels: [String: String]) -> String {
        if let m = url.range(of: #"slack\.com/archives/([A-Z0-9]+)/p\d+"#, options: .regularExpression) {
            let id = String(url[m]).split(separator: "/")[2]
            if let name = channels[String(id)] { return "Message in #\(name)" }
            return "Slack message"
        }
        guard let u = URL(string: url), let host = u.host else { return url }
        // Host and the first path segment: "figma.com/design…", "github.com/eri…".
        let segments = u.path.split(separator: "/").map(String.init)
        var label = host.replacingOccurrences(of: "www.", with: "")
        if let first = segments.first {
            label += "/" + (first.count > 18 ? String(first.prefix(18)) : first)
            if segments.count > 1 || first.count > 18 || u.query != nil { label += "…" }
        } else if u.query != nil {
            label += "/…"
        }
        return label
    }

    /// Slack keeps a shortened URL as a link's text ("figma.com/design/…?node-id=…"): still bare.
    static func isBare(text: String?, url: String) -> Bool {
        guard let text, !text.isEmpty else { return true }
        if url.lowercased().contains(text.lowercased()) { return true }
        guard let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") else { return false }
        return !text.contains(" ") && text.lowercased().contains(host.lowercased())
    }

    /// A chip as attributed text, for the rich text renderer.
    static func chip(_ url: URL, label: String) -> AttributedString {
        var s = AttributedString(mark + label + mark)
        s.link = url
        style(&s)
        return s
    }

    static func styleChips(in text: inout AttributedString) {
        for run in text.runs where run.link != nil {
            let piece = String(text[run.range].characters)
            if piece.hasPrefix(mark) && piece.hasSuffix(mark) {
                var chip = AttributedString(text[run.range])
                style(&chip)
                text.replaceSubrange(run.range, with: chip)
            }
        }
    }

    private static func style(_ s: inout AttributedString) {
        s.foregroundColor = Soot.lime
    }
}

/// Block Kit `rich_text` turned into styled text. It is the faithful source: `text` loses
/// list markers, code blocks and quote structure, which readers need.
enum SlackRichText {
    /// Nil when the message carries no rich text block, so the caller falls back to `text`.
    static func render(_ blocks: [SlackBlock]?, users: [String: SlackUser], channels: [String: String] = [:]) -> AttributedString? {
        let rich = (blocks ?? []).filter { $0.type == "rich_text" }
        guard !rich.isEmpty else { return nil }
        var out = AttributedString()
        for block in rich {
            for element in block.elements ?? [] { append(element, to: &out, users: users, channels: channels) }
        }
        while out.characters.last?.isNewline == true { out.removeSubrange(out.index(beforeCharacter: out.endIndex)..<out.endIndex) }
        return out.characters.isEmpty ? nil : out
    }

    private static func append(_ e: SlackRichElement, to out: inout AttributedString, users: [String: SlackUser], channels: [String: String]) {
        func startBlock() {
            if !out.characters.isEmpty, out.characters.last?.isNewline != true { out.append(AttributedString("\n")) }
        }
        switch e.type {
        case "rich_text_section":
            for leaf in e.elements ?? [] { out.append(render(leaf, users: users, channels: channels)) }
        case "rich_text_list":
            startBlock()
            let ordered = e.listStyle == "ordered"
            let indent = String(repeating: "    ", count: e.indent ?? 0)
            for (n, item) in (e.elements ?? []).enumerated() {
                if n > 0 { out.append(AttributedString("\n")) }
                var marker = AttributedString(indent + (ordered ? "\(n + 1).  " : "•  "))
                marker.foregroundColor = .secondary
                out.append(marker)
                for leaf in item.elements ?? [] { out.append(render(leaf, users: users, channels: channels)) }
            }
        case "rich_text_quote":
            startBlock()
            var quoted = AttributedString()
            for leaf in e.elements ?? [] { quoted.append(render(leaf, users: users, channels: channels)) }
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
            for leaf in e.elements ?? [] { code.append(render(leaf, users: users, channels: channels)) }
            code.inlinePresentationIntent = .code
            out.append(code)
        default:
            for leaf in e.elements ?? [] { out.append(render(leaf, users: users, channels: channels)) }
        }
    }

    private static func render(_ leaf: SlackRichElement, users: [String: SlackUser], channels: [String: String]) -> AttributedString {
        var s: AttributedString
        switch leaf.type {
        case "text": s = autolinked(leaf.text ?? "", channels: channels)
        case "link":
            let url = leaf.url.flatMap(URL.init(string:))
            // A link is "bare" when its text is the URL or a piece of it (Slack keeps what was typed).
            if let url, SlackLinks.isBare(text: leaf.text, url: leaf.url ?? "") {
                s = SlackLinks.chip(url, label: SlackLinks.plainLabel(leaf.url ?? "", channels: channels))
            } else {
                s = AttributedString(leaf.text ?? "")
                if let url { s.link = url }
            }
        case "user":
            s = AttributedString("@" + (leaf.user_id.flatMap { users[$0]?.name } ?? leaf.user_id ?? "user"))
            s.inlinePresentationIntent = .stronglyEmphasized
        case "channel":
            s = AttributedString("#" + (leaf.name ?? leaf.channel_id.flatMap { channels[$0] } ?? "channel"))
            s.inlinePresentationIntent = .stronglyEmphasized
        case "broadcast":
            s = AttributedString("@" + (leaf.range ?? "here"))
            s.inlinePresentationIntent = .stronglyEmphasized
        case "emoji":
            s = AttributedString(leaf.unicode.flatMap(emoji) ?? leaf.name.flatMap(SlackMarkup.unicode) ?? "")
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

    /// URLs typed as plain text (Slack leaves them unlinked inside quotes) become chips.
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func autolinked(_ text: String, channels: [String: String]) -> AttributedString {
        guard let detector, text.contains("://") else { return AttributedString(text) }
        let ns = text as NSString
        var out = AttributedString()
        var last = 0
        for m in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let url = m.url, url.scheme?.hasPrefix("http") == true else { continue }
            out.append(AttributedString(ns.substring(with: NSRange(location: last, length: m.range.location - last))))
            out.append(SlackLinks.chip(url, label: SlackLinks.plainLabel(url.absoluteString, channels: channels)))
            last = m.range.location + m.range.length
        }
        out.append(AttributedString(ns.substring(from: last)))
        return out
    }

    /// "1f44d-1f3fb" → 👍🏻
    private static func emoji(_ codes: String) -> String? {
        let scalars = codes.split(separator: "-").compactMap { UInt32($0, radix: 16).flatMap(Unicode.Scalar.init) }
        return scalars.isEmpty ? nil : String(String.UnicodeScalarView(scalars))
    }
}

/// What a row can do to its message, provided by the project page.
struct SlackMessageActions {
    var reply: (SlackMessage, String) async throws -> Void = { _, _ in }
    var react: (SlackMessage, String, Bool) async throws -> Void = { _, _, _ in }
    var replies: (SlackMessage) async throws -> [SlackMessage] = { _ in [] }
}

/// The channel's latest messages read like Slack: oldest at the top, newest at the bottom,
/// consecutive messages from one person grouped under one name and avatar. Threads open in
/// place; "Show earlier" walks back through the channel's history.
struct SlackThreadView: View {
    let messages: [SlackMessage]       // newest first, as the API returns them
    let users: [String: SlackUser]
    let domain: String?
    let channelID: String?
    var channelName: String?
    var shown = 8
    var hasEarlier = false
    var loadingEarlier = false
    /// The reading room: full text, day headings, threads in a pane beside the messages.
    var wide = false
    /// The content width of each layout. While the panel's frame animates from one to the
    /// other, each list is laid out at its own final width and clipped, so no message reflows.
    var widths: (rail: CGFloat, wide: CGFloat)? = nil
    /// The message to land on when the wide view opens (its `ts`).
    var focus: String?
    var customEmoji: [String: URL] = [:]
    var showEarlier: () -> Void = {}
    /// Compact view: a click on a message opens the wide view there.
    var openWide: ((SlackMessage) -> Void)?
    /// Compact view: opens the wide view on the latest messages.
    var expand: (() -> Void)?
    var actions = SlackMessageActions()
    @State private var openThread: SlackMessage?
    @AppStorage("slackThreadPaneWidth") private var paneWidth: Double = 320

    private var channels: [String: String] {
        guard let channelID, let channelName else { return [:] }
        return [channelID: channelName]
    }

    private var visible: [SlackMessage] { Array(messages.prefix(shown).reversed()) }

    /// The thread beside the room opens, closes or changes in one movement: slides in from
    /// the right over the aside, cross-fades to another thread, slides back out.
    private func setThread(_ m: SlackMessage?) { Motion.run(Motion.move) { openThread = m } }

    var body: some View {
        // Both layouts live in one place, so the view's state (the open thread) survives the
        // switch. The one leaving fades as the one arriving fades in (200 ms), each at its own
        // final width; the panel's growing frame clips the overflow. 8 px of headroom keep the
        // hover strip above the first message out of the clip.
        ZStack(alignment: .topLeading) {
            if wide {
                room.frame(width: widths?.wide, alignment: .leading)
                    .transition(.opacity)
            } else {
                list.frame(width: widths?.rail, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 8)
        .clipped()
        .padding(.top, -8)
        .motion(Motion.ui, fade: true, value: wide)
        .onReceive(NotificationCenter.default.publisher(for: .previewFirstSlackFile)) { _ in
            NotificationCenter.default.post(name: .previewSlackFile, object: firstFile())
        }
    }

    private var room: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollViewReader { proxy in
                ScrollView {
                    list.frame(maxWidth: 1200, alignment: .leading)
                    Color.clear.frame(height: 1).id("slack-end")
                }
                // Starts at the latest message and stays anchored there while the panel grows.
                .defaultScrollAnchor(.bottom)
                .background(OverlayScrollers())
                // Opens on the message that was clicked (once the panel has grown), else on the latest.
                .onAppear {
                    guard let focus else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + (Motion.reduced ? 0 : 0.4)) {
                        Motion.run(Motion.ui) { proxy.scrollTo(focus, anchor: .center) }
                    }
                }
                .onChange(of: focus) { _, ts in if let ts { Motion.run(Motion.ui) { proxy.scrollTo(ts, anchor: .center) } } }
            }
            .frame(maxWidth: 1200, maxHeight: .infinity, alignment: .topLeading)
            PaneHandle(width: $paneWidth)
            // Beside the messages: the open thread, or what the channel holds when none is open.
            Group {
                if let parent = openThread {
                    ThreadPane(parent: messages.first { $0.ts == parent.ts } ?? parent, user: parent.user.flatMap { users[$0] },
                               users: users, channels: channels, customEmoji: customEmoji,
                               permalink: permalink(parent), actions: actions) {
                        setThread(nil)
                    }
                    .transition(Motion.slide(from: .trailing))
                } else {
                    ChannelAside(messages: messages, users: users, channels: channels)
                        .transition(.opacity)
                }
            }
            .frame(width: paneWidth)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFirstSlackThread)) { _ in
            setThread(openThread == nil ? messages.prefix(shown).first { ($0.reply_count ?? 0) > 0 } : nil)
        }
        .onChange(of: messages.map(\.ts)) { _, ts in
            // The thread pane follows a message that scrolled out of the loaded range.
            if let parent = openThread, !ts.contains(parent.ts) { setThread(nil) }
        }
    }

    private func firstFile() -> SlackFile? {
        return messages.flatMap { $0.files ?? [] }.first { $0.isReadable && $0.url_private != nil }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if wide, hasEarlier || messages.count > shown {
                Group {
                    if loadingEarlier {
                        WaitingLine().padding(.horizontal, 8).padding(.bottom, 12)
                            .accessibilityElement().accessibilityLabel("Loading earlier messages")
                            .transition(.opacity)
                    } else {
                        Button("Show earlier", action: showEarlier)
                            .buttonStyle(PressButton()).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.lime)
                            .padding(.horizontal, 8).padding(.bottom, 12)
                            .modifier(FocusOutline(radius: 4))
                            .transition(.opacity)
                    }
                }
                .motion(Motion.ui, fade: true, value: loadingEarlier)
            }
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, m in
                let previous = index > 0 ? visible[index - 1] : nil
                let newDay = previous.map { !Calendar.current.isDate($0.date, inSameDayAs: m.date) } ?? true
                let grouped = !newDay && (previous.map { $0.user == m.user && m.date.timeIntervalSince($0.date) < 600 } ?? false)
                if newDay {
                    DayDivider(date: m.date).padding(.top, index == 0 ? 0 : (wide ? 22 : 16)).padding(.bottom, wide ? 10 : 6)
                }
                if m.isSystem {
                    SystemRow(message: m, user: m.user.flatMap { users[$0] }, users: users, channels: channels)
                        .padding(.top, newDay ? 0 : 10)
                        .id(m.ts)
                } else {
                    MessageRow(message: m, user: m.user.flatMap { users[$0] }, users: users, channels: channels,
                               customEmoji: customEmoji, grouped: grouped, wide: wide,
                               selected: openThread?.ts == m.ts || focus == m.ts, permalink: permalink(m),
                               actions: actions, openThread: wide ? { setThread($0) } : nil, openWide: openWide)
                        .padding(.top, grouped ? 2 : (newDay ? 0 : (wide ? 18 : 14)))
                        .id(m.ts)
                }
            }
            if !wide, let expand, messages.count > shown {
                Button(action: expand) {
                    HStack(spacing: 6) {
                        Text("Read the conversation")
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .handCursor()
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
                .padding(.horizontal, 8).padding(.top, 14)
                .modifier(FocusOutline(radius: 4))
                .help("Read the whole conversation (⌘⇧E)")
            }
        }
    }

    private func permalink(_ m: SlackMessage) -> URL? {
        guard let domain, let channelID else { return nil }
        return URL(string: "https://\(domain).slack.com/archives/\(channelID)/p\(m.ts.replacingOccurrences(of: ".", with: ""))")
    }
}

/// "Today", "Yesterday" or "Friday, 30 October" on a hairline, as Slack marks each day.
struct DayDivider: View {
    let date: Date

    private var label: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        return date.formatted(sameYear ? .dateTime.weekday(.wide).day().month(.wide)
                                       : .dateTime.weekday(.wide).day().month(.wide).year())
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Soot.line).frame(height: 1)
            Text(label)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
                .padding(.horizontal, 10).frame(height: 22)
                .overlay(Capsule().strokeBorder(Soot.line))
                .fixedSize()
            Rectangle().fill(Soot.line).frame(height: 1)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What the loaded conversation holds, for the wide view when no thread is open:
/// who talks here, the links shared, the files posted.
private struct ChannelAside: View {
    let messages: [SlackMessage]
    let users: [String: SlackUser]
    let channels: [String: String]
    @State private var allPeople = false

    private var people: [(user: SlackUser, count: Int)] {
        var counts: [String: Int] = [:]
        for m in messages { if let u = m.user { counts[u, default: 0] += 1 } }
        return counts.compactMap { id, n in users[id].map { ($0, n) } }
            .sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0.name < $1.0.name) }
    }

    private var links: [(message: SlackMessage, card: SlackAttachment, url: URL)] {
        messages.flatMap { m in
            (m.attachments ?? []).compactMap { c -> (SlackMessage, SlackAttachment, URL)? in
                guard !c.isEmpty, !c.isMessageUnfurl,
                      let u = (c.title_link ?? c.from_url ?? c.original_url).flatMap(URL.init(string:)) else { return nil }
                return (m, c, u)
            }
        }
    }

    private var files: [(message: SlackMessage, file: SlackFile)] { messages.flatMap { m in (m.files ?? []).map { (m, $0) } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("People", symbol: "person.2", count: people.count) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(allPeople ? people : Array(people.prefix(5)), id: \.user.id) { p in
                        HStack(spacing: 10) {
                            SlackAvatar(user: p.user, name: p.user.name, size: 24, radius: 6)
                            Text(p.user.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(p.count)").font(.system(size: 11)).foregroundStyle(Soot.muted).monospacedDigit()
                                .accessibilityLabel("^[\(p.count) message](inflect: true)")
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if people.count > 5 {
                        Button(allPeople ? "Show fewer" : "Show all \(people.count)") { allPeople.toggle() }
                            .buttonStyle(.plain).handCursor().font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.lime)
                            .padding(.top, 2).modifier(FocusOutline(radius: 4))
                    }
                }
            }
            if !links.isEmpty {
                section("Links", symbol: "link", count: links.count) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(links.prefix(6).enumerated()), id: \.offset) { _, l in
                            let host = (l.url.host ?? "").replacingOccurrences(of: "www.", with: "")
                            Link(destination: l.url) {
                                HStack(alignment: .center, spacing: 10) {
                                    Text(String(host.prefix(1)).uppercased())
                                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.black.opacity(0.7))
                                        .frame(width: 24, height: 24)
                                        .background(PersonTint.color(for: host), in: RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(SlackMarkup.render(LinkPreview.excerpt(l.card.title ?? l.card.fallback, lines: 1) ?? SlackLinks.plainLabel(l.url.absoluteString, channels: channels), users: [:]))
                                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.ink).tint(Soot.ink).lineLimit(1)
                                        Text(host + " · " + l.message.date.formatted(.relative(presentation: .named)))
                                            .font(.system(size: 11)).foregroundStyle(Soot.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8).frame(height: 40)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .handCursor()
                            .modifier(FocusOutline(radius: 8))
                            .help(l.url.absoluteString)
                        }
                    }
                }
            }
            if !files.isEmpty {
                section("Files", symbol: "paperclip", count: files.count) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(files.prefix(6), id: \.file.id) { f in AsideFileRow(file: f.file, date: f.message.date) }
                    }
                }
            }
            if people.isEmpty && links.isEmpty && files.isEmpty {
                Text("Open a thread to read it here.").font(.system(size: 13)).foregroundStyle(Soot.muted)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About this conversation")
    }

    private func section<Content: View>(_ title: String, symbol: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink).accessibilityAddTraits(.isHeader)
                Text("\(count)").font(.system(size: 12)).foregroundStyle(Soot.muted).monospacedDigit()
            }
            content()
        }
    }
}

/// A file in the aside: a small thumbnail for pictures, a glyph otherwise; opens the preview.
private struct AsideFileRow: View {
    @EnvironmentObject var app: AppState
    let file: SlackFile
    let date: Date
    @State private var thumb: CGImage?

    var body: some View {
        Button { NotificationCenter.default.post(name: .previewSlackFile, object: file) } label: {
            HStack(spacing: 10) {
                Group {
                    if let thumb {
                        Image(decorative: thumb, scale: 2).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: file.isImage ? "photo" : "doc").font(.system(size: 12)).foregroundStyle(Soot.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Soot.surface)
                    }
                }
                .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.displayName).font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                    Text([file.filetype?.uppercased(), file.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
                          date.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(Soot.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .handCursor()
        .modifier(FocusOutline(radius: 8))
        .help("Preview \(file.displayName)")
        .disabled(!file.isReadable || file.url_private == nil)
        .task(id: file.id) {
            guard file.isImage, let url = file.thumb_360.flatMap(URL.init(string:)) else { return }
            thumb = try? await app.withSlack { await SlackMediaCache.shared.thumbnail(url, fileID: file.id, variant: "360", maxPixels: 720, client: $0) }
        }
    }
}

/// A channel event ("renamed the channel…", "pinned a message"): one quiet line, no card.
private struct SystemRow: View {
    let message: SlackMessage
    let user: SlackUser?
    let users: [String: SlackUser]
    let channels: [String: String]

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                SlackAvatar(user: user, name: user?.name ?? "S", size: 24, radius: 6)
                    .padding([.bottom, .trailing], 5)
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Soot.limeInk)
                    .frame(width: 16, height: 16)
                    .background(Soot.lime, in: Circle())
                    .overlay(Circle().strokeBorder(Soot.surface, lineWidth: 2))
            }
            .frame(width: 32, height: 30)
            (Text(user?.name ?? "Slack").fontWeight(.semibold).foregroundColor(Soot.ink) + Text(" ") +
             Text(SlackMarkup.render(stripLeadingMention(message.text ?? ""), users: users.mapValues(\.name), channels: channels)))
                .font(.system(size: 13)).foregroundStyle(Soot.muted).tint(Soot.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(message.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(Soot.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch message.subtype {
        case "channel_name", "group_name": "pencil"
        case "pinned_item", "unpinned_item": "pin.fill"
        case "channel_topic", "channel_purpose", "group_topic", "group_purpose": "text.quote"
        case "bot_add", "bot_remove": "puzzlepiece.fill"
        case "channel_archive", "channel_unarchive": "archivebox.fill"
        default: "info"
        }
    }

    /// Slack starts these with the actor's mention; the name is already shown.
    private func stripLeadingMention(_ text: String) -> String {
        text.replacingOccurrences(of: #"^<@[A-Z0-9]+>\s*"#, with: "", options: .regularExpression)
    }
}

/// Presents a Slack file in a sheet when a thumbnail or file row asks for it.
struct FilePreviewHost: ViewModifier {
    @Binding var preview: SlackFile?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .previewSlackFile)) { note in
                // The lightbox pops in over a dimming page (200 ms ease-out), leaves faster (150 ms ease-in).
                let file = note.object as? SlackFile   // nil closes it
                Motion.run(file == nil ? Motion.exit : Motion.ui, fade: true) { preview = file }
            }
            .overlay {
                if let file = preview {
                    FileLightbox(file: file) { Motion.run(Motion.exit, fade: true) { preview = nil } }
                }
            }
    }
}

extension Notification.Name {
    /// Asks the nearest `FilePreviewHost` to show a `SlackFile`.
    static let previewSlackFile = Notification.Name("dever.previewSlackFile")
    /// Snapshots: previews the first readable file of the conversation.
    static let previewFirstSlackFile = Notification.Name("dever.previewFirstSlackFile")
    /// Snapshots: opens (or closes) the first thread in the wide view.
    static let openFirstSlackThread = Notification.Name("dever.openFirstSlackThread")
}

/// The divider between messages and the side pane: drag to resize, double-click to reset.
private struct PaneHandle: View {
    @Binding var width: Double
    @State private var hovering = false
    @State private var start: Double?

    var body: some View {
        Rectangle().fill(hovering || start != nil ? Soot.lime : Soot.line)
            .frame(width: 2)
            .opacity(hovering || start != nil ? 1 : 0.6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .overlay(CursorArea(cursor: .resizeLeftRight))
            .onHover { hovering = $0 }
            // Global coordinates: the handle itself moves while dragging, so a local
            // translation would feed back into the width and make everything shake.
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    if start == nil { start = width }
                    width = min(560, max(260, (start ?? width) - (value.location.x - value.startLocation.x)))
                }
                .onEnded { _ in start = nil })
            .transaction { $0.animation = nil }
            .onTapGesture(count: 2) { width = 320 }
            .accessibilityElement()
            .accessibilityLabel("Pane width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                width = min(560, max(260, width + (direction == .increment ? 20 : -20)))
            }
    }
}

/// The people who answered, as a short stack of small pictures.
private struct ReplierAvatars: View {
    let ids: [String]
    let users: [String: SlackUser]
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(ids.prefix(4), id: \.self) { id in
                SlackAvatar(user: users[id], name: users[id]?.name ?? "?", size: size, radius: size / 2)
                    .overlay(Circle().strokeBorder(Soot.surface, lineWidth: 1.5))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A thread beside the messages in the wide view: the parent, its replies, a composer.
private struct ThreadPane: View {
    @EnvironmentObject var app: AppState
    let parent: SlackMessage
    let user: SlackUser?
    let users: [String: SlackUser]
    let channels: [String: String]
    var customEmoji: [String: URL] = [:]
    let permalink: URL?
    let actions: SlackMessageActions
    let close: () -> Void
    @State private var replies: [SlackMessage]?
    @State private var failed = false
    @State private var draft = ""
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Thread").font(.system(size: 15, weight: .semibold)).foregroundStyle(Soot.ink)
                        .accessibilityAddTraits(.isHeader)
                    (Text("Replies to \(user?.name ?? "a message")") +
                     (parent.reply_count.map { Text(" · ") + Text("^[\($0) reply](inflect: true)") } ?? Text("")))
                        .font(.system(size: 12)).foregroundStyle(Soot.muted)
                }
                Spacer()
                if let permalink {
                    Link(destination: permalink) { Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)) }
                        .foregroundStyle(Soot.muted).help("Open the thread in Slack").accessibilityLabel("Open the thread in Slack")
                }
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.ink)
                        .frame(width: 28, height: 28).background(Soot.ground, in: Circle())
                }
                .buttonStyle(.plain)
                .modifier(FocusOutline(radius: 14))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close the thread")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: 0).background(OverlayScrollers())
                    HStack(alignment: .top, spacing: 10) {
                        SlackAvatar(user: user, name: user?.name ?? "App", size: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(user?.name ?? "App").font(.system(size: 14, weight: .bold)).foregroundStyle(Soot.ink)
                                Text(parent.date.formatted(.relative(presentation: .named))).font(.system(size: 12)).foregroundStyle(Soot.muted)
                            }
                            MessageBody(message: parent, users: users, channels: channels, expanded: .constant(true))
                            MessageExtras(message: parent, channels: channels, users: users)
                    ReactionsBar(message: parent, customEmoji: customEmoji, actions: actions)
                        }
                    }
                    Rectangle().fill(Soot.line).frame(height: 1)
                    ThreadReplies(replies: replies, failed: failed, users: users, channels: channels, customEmoji: customEmoji, actions: actions, bare: true)
                }
            }
            .frame(maxHeight: .infinity)
            // Another thread picked while this one is open: the pane stays, its content
            // cross-fades (200 ms) instead of a second pane sliding in over the first.
            .id(parent.ts)
            .transition(.opacity)
            .motion(Motion.ui, fade: true, value: parent.ts)
            ReplyComposer(draft: $draft, sending: sending, autofocus: false, send: { await send() }, cancel: { draft = "" })
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Soot.ground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Soot.line))
        .task(id: parent.ts) { replies = nil; draft = ""; await load() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thread")
    }

    private func load() async {
        failed = false
        do { replies = try await actions.replies(parent) } catch { failed = true }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        do {
            try await actions.reply(parent, text)
            draft = ""
            await load()
        } catch { app.report(error) }
    }
}

/// One line to answer in a thread: Return sends, Escape clears.
private struct ReplyComposer: View {
    @Binding var draft: String
    let sending: Bool
    var autofocus = true
    let send: () async -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    private var empty: Bool { draft.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Reply in thread", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Soot.ink)
                .focused($focused)
                .onSubmit { Task { await send() } }
                .onExitCommand(perform: cancel)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Soot.lime : Soot.edge))
                .disabled(sending)
            Button("Send") { Task { await send() } }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(empty || sending ? Soot.muted : Soot.limeInk)
                .padding(.horizontal, 10).frame(height: 28)
                .background(empty || sending ? Soot.ground : Soot.lime, in: Capsule())
                .disabled(empty || sending)
                .modifier(FocusOutline(radius: 14))
        }
        .padding(.top, 4)
        .onAppear { if autofocus { focused = true } }
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
    let channels: [String: String]
    var customEmoji: [String: URL] = [:]
    let grouped: Bool
    var wide = false
    var selected = false
    let permalink: URL?
    let actions: SlackMessageActions
    /// In the wide view the thread opens in a pane beside the list instead of inline.
    var openThread: ((SlackMessage) -> Void)? = nil
    /// In the compact view a click on the message opens the wide view on it.
    var openWide: ((SlackMessage) -> Void)? = nil
    @State private var picking = false
    @State private var expanded = false
    @State private var hovering = false
    @State private var threadOpen = false
    @State private var thread: [SlackMessage]?
    @State private var threadFailed = false
    @State private var replying = false
    @State private var draft = ""
    @State private var sending = false
    @State private var reactions: [SlackReaction] = []
    @FocusState private var stripFocus: Int?

    private var stripShown: Bool { hovering || stripFocus != nil || picking }

    private var author: String { user?.name ?? "App" }
    private var me: String? { app.slack?.userID }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if grouped {
                    Text(message.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10)).foregroundStyle(Soot.muted)
                        .opacity(hovering ? 1 : 0)
                } else {
                    SlackAvatar(user: user, name: author, size: wide ? 36 : 32)
                }
            }
            .frame(width: wide ? 36 : 32, alignment: .center)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if !grouped {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(author).font(.system(size: 14, weight: .bold)).foregroundStyle(Soot.ink)
                        // Under a day heading the clock time says more than "3 weeks ago".
                        Text(wide ? message.date.formatted(date: .omitted, time: .shortened)
                                  : message.date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 12)).foregroundStyle(Soot.muted)
                            .help(message.date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                MessageBody(message: message, users: users, channels: channels, expanded: wide ? .constant(true) : $expanded)
                MessageExtras(message: message, channels: channels, users: users)
                if !reactions.isEmpty {
                    ReactionPills(reactions: reactions, me: me, customEmoji: customEmoji) { toggle($0) }
                }
                HStack(spacing: 12) {
                    if !wide, (message.text?.count ?? 0) > 240 {
                        Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
                    }
                    if let r = message.reply_count, r > 0 {
                        Button {
                            if let openThread { openThread(message); return }
                            threadOpen.toggle()
                            if threadOpen, thread == nil { Task { await loadThread() } }
                        } label: {
                            HStack(spacing: 6) {
                                if let ids = message.reply_users, !ids.isEmpty {
                                    ReplierAvatars(ids: ids, users: users)
                                } else {
                                    Image(systemName: threadOpen ? "chevron.down" : "bubble.left.and.bubble.right").font(.system(size: 11))
                                }
                                Text("^[\(r) reply](inflect: true)")
                                if let last = message.latest_reply.flatMap(Double.init), wide {
                                    Text("Last reply \(Date(timeIntervalSince1970: last).formatted(.relative(presentation: .named)))")
                                        .font(.system(size: 12, weight: .regular)).foregroundStyle(Soot.muted)
                                }
                                if openThread != nil { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)) }
                            }
                        }
                        .buttonStyle(.plain)
                        .handCursor()
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Soot.lime)
                        .modifier(FocusOutline(radius: 4))
                        .accessibilityLabel(threadOpen ? "Hide replies" : "Show \(r) replies")
                    }
                }
                .padding(.top, 4)
                if threadOpen, openThread == nil {
                    ThreadReplies(replies: thread, failed: threadFailed, users: users, channels: channels, customEmoji: customEmoji, actions: actions)
                }
                if replying, openThread == nil {
                    ReplyComposer(draft: $draft, sending: sending, send: { await send() }, cancel: { replying = false; draft = "" })
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .padding(.trailing, 4)
        .background(selected ? Soot.ground : (hovering ? Soot.ground.opacity(0.6) : Color.clear), in: RoundedRectangle(cornerRadius: 6))
        .padding(.leading, selected ? 8 : 0)
        .overlay(alignment: .leading) {
            if selected { RoundedRectangle(cornerRadius: 2).fill(Soot.lime).frame(width: 3).padding(.vertical, 6).transition(.opacity) }
        }
        // Hover is a 120 ms tone; the lime bar of the selected message fades in and the row
        // steps aside for it (200 ms, fade only under Reduce Motion).
        .motion(Motion.quick, fade: true, value: hovering)
        .motion(Motion.ui, value: selected)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { if let openWide { openWide(message) } }, including: openWide == nil ? .none : .all)
        .help(openWide == nil ? "" : "Open the conversation at this message")
        .overlay(alignment: .topTrailing) {
            toolbar.opacity(stripShown ? 1 : 0).offset(x: 0, y: -6)
                .motion(Motion.quick, fade: true, value: stripShown)
        }
        .onHover { hovering = $0 }
        .onAppear { reactions = message.reactions ?? [] }
        .onChange(of: message.reactions) { _, new in reactions = new ?? [] }
        .accessibilityElement(children: .contain)
    }

    /// Slack's hover strip, reduced to what matters here: two reactions and a menu.
    private var toolbar: some View {
        HStack(spacing: 2) {
            ForEach(Array(["+1", "heart"].enumerated()), id: \.element) { i, name in
                let on = mine(name)
                Button { toggle(name) } label: {
                    Text(SlackMarkup.emoji[name] ?? name).font(.system(size: 13))
                        .frame(width: 26, height: 24)
                        .background(on ? Soot.lime.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .handCursor()
                .focused($stripFocus, equals: i)
                .modifier(FocusOutline(radius: 5))
                .accessibilityLabel(on ? "Remove \(SlackMarkup.reactionName(name))" : "React with \(SlackMarkup.reactionName(name))")
            }
            Button { picking.toggle() } label: {
                Image(systemName: "face.smiling").font(.system(size: 13)).foregroundStyle(Soot.ink)
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .handCursor()
            .focused($stripFocus, equals: 3)
            .modifier(FocusOutline(radius: 5))
            .accessibilityLabel("Add a reaction")
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                EmojiPicker(customEmoji: customEmoji, mine: Set(reactions.filter { mine($0.name) }.map(\.name))) { name in
                    picking = false
                    toggle(name)
                }
            }
            Menu {
                Button("Reply in thread") {
                    if let openThread { openThread(message) } else { replying = true }
                }
                if let permalink { Link("Open in Slack", destination: permalink) }
                if let permalink {
                    Button("Copy link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(permalink.absoluteString, forType: .string)
                    }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.ink)
                    .frame(width: 26, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .handCursor()
            .focused($stripFocus, equals: 2)
            .modifier(FocusOutline(radius: 5))
            .accessibilityLabel("More actions")
        }
        .padding(2)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Soot.line))
    }

    private func mine(_ name: String) -> Bool {
        guard let me else { return false }
        return reactions.first { $0.name == name }?.users?.contains(me) ?? false
    }

    /// Optimistic: the pill changes at once, the request follows.
    private func toggle(_ name: String) {
        let on = !mine(name)
        if let i = reactions.firstIndex(where: { $0.name == name }) {
            var r = reactions[i]
            r.count += on ? 1 : -1
            var users = r.users ?? []
            if on { if let me { users.append(me) } } else { users.removeAll { $0 == me } }
            r.users = users
            if r.count <= 0 { reactions.remove(at: i) } else { reactions[i] = r }
        } else if on {
            reactions.append(SlackReaction(name: name, count: 1, users: me.map { [$0] }))
        }
        Task {
            do { try await actions.react(message, name, on) } catch { app.report(error); reactions = message.reactions ?? [] }
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        do {
            try await actions.reply(message, text)
            draft = ""
            replying = false
            threadOpen = true
            await loadThread()
        } catch { app.report(error) }
    }

    private func loadThread() async {
        threadFailed = false
        do { thread = try await actions.replies(message) } catch { threadFailed = true }
    }
}

/// Reactions under a message, as Slack shows them: emoji and count in a small bordered pill,
/// the ones you gave on a lime wash. Hover lifts it, click toggles.
private struct ReactionPills: View {
    let reactions: [SlackReaction]
    let me: String?
    var customEmoji: [String: URL] = [:]
    let toggle: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(reactions) { r in
                ReactionPill(reaction: r, on: me.map { r.users?.contains($0) ?? false } ?? false,
                             custom: customEmoji[r.name.split(separator: ":").first.map(String.init) ?? r.name]) { toggle(r.name) }
            }
        }
        .padding(.top, 4)
    }
}

private struct ReactionPill: View {
    let reaction: SlackReaction
    let on: Bool
    let custom: URL?
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                EmojiGlyph(name: reaction.name, custom: custom, size: 14)
                Text("\(reaction.count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(on ? Soot.lime : Soot.ink.opacity(0.85))
            }
            .padding(.horizontal, 8).frame(height: 24)
            .background(on ? Soot.lime.opacity(hovering ? 0.24 : 0.14) : (hovering ? Soot.surface : Soot.ground), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Soot.lime : (hovering ? Soot.ink.opacity(0.6) : Soot.edge.opacity(0.6))))
        }
        .buttonStyle(ReactionPillStyle())
        .handCursor()
        .onHover { hovering = $0 }
        .modifier(FocusOutline(radius: 12))
        .help(on ? "Remove your \(SlackMarkup.reactionName(reaction.name)) reaction" : "React with \(SlackMarkup.reactionName(reaction.name))")
        .accessibilityLabel("\(SlackMarkup.reactionName(reaction.name)), \(reaction.count)\(on ? ", including you" : "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A standard emoji as text, a custom one as its picture, an unknown one as its name.
struct EmojiGlyph: View {
    let name: String
    var custom: URL?
    var size: CGFloat = 14
    @State private var image: CGImage?

    var body: some View {
        if let text = SlackMarkup.unicode(name) {
            Text(text).font(.system(size: size - 1))
        } else if custom != nil {
            Group {
                if let image {
                    Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(Soot.line)
                }
            }
            .frame(width: size + 2, height: size + 2)
            .task(id: custom) {
                guard let custom else { return }
                image = await SlackMediaCache.shared.publicImage(custom, maxPixels: Int(size * 4))
            }
        } else {
            Text(":\(name):").font(.system(size: size - 4, weight: .medium)).foregroundStyle(Soot.muted).lineLimit(1)
        }
    }
}

/// A small grid of reactions to pick from: the usual ones, the team's own, and a search over all.
struct EmojiPicker: View {
    let customEmoji: [String: URL]
    let mine: Set<String>
    let choose: (String) -> Void
    @State private var query = ""
    @FocusState private var searching: Bool

    private static let usual = ["+1", "heart", "tada", "eyes", "white_check_mark", "pray", "joy", "fire", "rocket", "raised_hands",
                                "clap", "100", "thinking_face", "muscle", "sparkles", "bulb", "wave", "ok_hand", "sob", "heavy_check_mark",
                                "x", "warning", "hourglass_flowing_sand", "point_up", "handshake", "star", "coffee", "bug"]

    private var results: [(name: String, custom: URL?)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "_")
        if q.isEmpty {
            return Self.usual.map { ($0, nil) } + customEmoji.keys.sorted().prefix(32).map { ($0, customEmoji[$0]) }
        }
        let custom = customEmoji.keys.filter { $0.contains(q) }.sorted().map { ($0, customEmoji[$0]) }
        let standard = SlackEmojiTable.names.keys.filter { $0.contains(q) }.sorted { ($0.hasPrefix(q) ? 0 : 1, $0) < ($1.hasPrefix(q) ? 0 : 1, $1) }
            .prefix(48).map { ($0, nil as URL?) }
        return custom + standard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search emoji", text: $query)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Soot.ink)
                .focused($searching)
                .padding(.horizontal, 10).frame(height: 30)
                .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(searching ? Soot.lime : Soot.edge))
            if results.isEmpty {
                Text("No emoji for “\(query)”").font(.system(size: 12)).foregroundStyle(Soot.muted).padding(.vertical, 8)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 2), count: 8), spacing: 2) {
                    ForEach(results, id: \.name) { r in
                        Button { choose(r.name) } label: {
                            EmojiGlyph(name: r.name, custom: r.custom, size: 18)
                                .frame(width: 32, height: 32)
                                .background(mine.contains(r.name) ? Soot.lime.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .handCursor()
                        .modifier(FocusOutline(radius: 6))
                        .help(SlackMarkup.reactionName(r.name))
                        .accessibilityLabel(SlackMarkup.reactionName(r.name))
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 8 * 34 + 24)
        .background(Soot.surface)
        .onAppear { searching = true }
    }
}

/// A pill that presses to 0.96 and lifts a tone on hover; no motion under Reduce Motion.
private struct ReactionPillStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The text of a message: rich text when Slack sent blocks, mrkdwn otherwise.
private struct MessageBody: View {
    let message: SlackMessage
    let users: [String: SlackUser]
    var channels: [String: String] = [:]
    @Binding var expanded: Bool

    var body: some View {
        let text = SlackRichText.render(message.blocks, users: users, channels: channels)
            ?? SlackMarkup.render(message.text ?? "", users: users.mapValues(\.name), channels: channels)
        if !text.characters.isEmpty {
            RichTextLabel(text: text, size: 14, color: Soot.ink.opacity(0.92), lineLimit: expanded ? 0 : 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What a message carries besides its text: pictures, files, link previews.
private struct MessageExtras: View {
    let message: SlackMessage
    var channels: [String: String] = [:]
    var users: [String: SlackUser] = [:]

    var body: some View {
        let files = message.files ?? []
        let cards = (message.attachments ?? []).filter { !$0.isEmpty }
        if !files.isEmpty || !cards.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(files) { file in
                    if file.isReadable, file.isImage { SlackImage(file: file) } else { FileRow(file: file) }
                }
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in LinkPreview(card: card, channels: channels, users: users) }
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
                Button { NotificationCenter.default.post(name: .previewSlackFile, object: file) } label: {
                    Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: width, height: width / ratio)
                }
                .buttonStyle(.plain)
                .handCursor()
                .help("Preview \(file.displayName)")
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
        if file.isReadable, file.url_private != nil {
            Button { NotificationCenter.default.post(name: .previewSlackFile, object: file) } label: { row }
                .buttonStyle(.plain).handCursor().modifier(FocusOutline(radius: 8))
                .help("Preview \(file.displayName)")
        } else if let url = file.permalink.flatMap(URL.init(string:)) {
            Link(destination: url) { row }.buttonStyle(.plain).handCursor().modifier(FocusOutline(radius: 8))
                .help("Open in Slack")
        } else {
            row
        }
    }
}

/// A link unfurl: the site, the title and a line of its text, with a bar in the site's colour.
private struct LinkPreview: View {
    let card: SlackAttachment
    var channels: [String: String] = [:]
    var users: [String: SlackUser] = [:]
    @State private var image: CGImage?

    private var names: [String: String] { users.mapValues(\.name) }
    private var quotedDate: String? {
        card.ts.flatMap { Double($0.value) }.map { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened) }
    }

    /// Slack messages quoted from another channel are not linked: without access the link
    /// only opens an error. The quote itself already carries the content.
    private var link: URL? {
        if card.isMessageUnfurl, card.channel_id.map({ channels[$0] == nil }) ?? true { return nil }
        return (card.title_link ?? card.from_url ?? card.original_url).flatMap(URL.init(string:))
    }

    /// Three lines at most, blank lines dropped: a clamp alone keeps the full height in a fixed-size stack.
    static func excerpt(_ text: String?, lines max: Int = 3) -> String? {
        guard let text else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let out = lines.prefix(max).joined(separator: "\n")
        return out.isEmpty ? nil : String(out.prefix(max * 100))
    }
    private var bar: Color { card.color.flatMap(Color.init(hex:)) ?? Soot.line }

    var body: some View {
        let body = HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(bar).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                if card.isMessageUnfurl {
                    // A quoted message: who, where, when; then its text with mentions resolved.
                    // Its `title` repeats the text with a date prefix, so it is left out.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "quote.opening").font(.system(size: 9, weight: .bold)).foregroundStyle(Soot.muted)
                        Text(card.author_name ?? "Slack message").font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.ink)
                        Text([card.channel_name.map { "#\($0)" }, quotedDate].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                    if let text = Self.excerpt(card.text ?? card.fallback, lines: 4) {
                        Text(SlackMarkup.render(text, users: names, channels: channels)).font(.system(size: 13))
                            .foregroundStyle(Soot.ink.opacity(0.88)).tint(Soot.lime).lineLimit(4)
                    }
                } else {
                    if let site = card.service_name ?? card.author_name {
                        Text(site).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                    if let title = Self.excerpt(card.title ?? card.pretext ?? card.fallback, lines: 2) {
                        Text(SlackMarkup.render(title, users: names)).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Soot.ink).tint(Soot.ink).lineLimit(2)
                    }
                    if let text = Self.excerpt(card.text) {
                        Text(SlackMarkup.render(text, users: names)).font(.system(size: 12)).foregroundStyle(Soot.ink.opacity(0.8))
                            .tint(Soot.lime).lineLimit(3)
                    }
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
            Link(destination: link) { body }.buttonStyle(.plain).handCursor().modifier(FocusOutline(radius: 8))
        } else {
            body
        }
    }
}

/// A message's reactions with their own optimistic state: click a pill to add or remove yours.
private struct ReactionsBar: View {
    @EnvironmentObject var app: AppState
    let message: SlackMessage
    let customEmoji: [String: URL]
    let actions: SlackMessageActions
    @State private var reactions: [SlackReaction] = []

    private var me: String? { app.slack?.userID }

    var body: some View {
        Group {
            if !reactions.isEmpty {
                ReactionPills(reactions: reactions, me: me, customEmoji: customEmoji) { toggle($0) }
            }
        }
        .onAppear { reactions = message.reactions ?? [] }
        .onChange(of: message.reactions) { _, new in reactions = new ?? [] }
    }

    private func toggle(_ name: String) {
        guard let me else { return }
        let on = !(reactions.first { $0.name == name }?.users?.contains(me) ?? false)
        if let i = reactions.firstIndex(where: { $0.name == name }) {
            var r = reactions[i]
            r.count += on ? 1 : -1
            var users = r.users ?? []
            if on { users.append(me) } else { users.removeAll { $0 == me } }
            r.users = users
            if r.count <= 0 { reactions.remove(at: i) } else { reactions[i] = r }
        } else if on {
            reactions.append(SlackReaction(name: name, count: 1, users: [me]))
        }
        Task {
            do { try await actions.react(message, name, on) } catch { app.report(error); reactions = message.reactions ?? [] }
        }
    }
}

/// A thread's replies, under their parent and set off by a line.
private struct ThreadReplies: View {
    let replies: [SlackMessage]?
    let failed: Bool
    let users: [String: SlackUser]
    var channels: [String: String] = [:]
    var customEmoji: [String: URL] = [:]
    var actions = SlackMessageActions()
    /// Without the indent and bar, for the thread pane.
    var bare = false

    var body: some View {
        VStack(alignment: .leading, spacing: bare ? 14 : 10) {
            if failed {
                Text("Couldn't load the replies.").font(.system(size: 12)).foregroundStyle(Soot.muted)
            } else if let replies {
                ForEach(replies) { reply in
                    let user = reply.user.flatMap { users[$0] }
                    HStack(alignment: .top, spacing: 8) {
                        SlackAvatar(user: user, name: user?.name ?? "App", size: bare ? 28 : 22, radius: bare ? 7 : 6)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(user?.name ?? "App").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                                Text(reply.date.formatted(.relative(presentation: .named))).font(.system(size: 11)).foregroundStyle(Soot.muted)
                            }
                            MessageBody(message: reply, users: users, channels: channels, expanded: .constant(true))
                            MessageExtras(message: reply, channels: channels, users: users)
                            ReactionsBar(message: reply, customEmoji: customEmoji, actions: actions)
                        }
                    }
                }
            } else {
                WaitingLine().frame(width: 120).accessibilityElement().accessibilityLabel("Loading replies")
            }
        }
        .padding(.leading, bare ? 0 : 10)
        .padding(.top, bare ? 0 : 6)
        .overlay(alignment: .leading) { if !bare { Rectangle().fill(Soot.line).frame(width: 2).padding(.top, 6) } }
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
