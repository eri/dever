import AppKit
import SwiftUI

/// What the composer hands over: `text` is the mrkdwn Slack shows in notifications and
/// falls back on; `blocks` is the same message as rich_text JSON, only when it carries
/// formatting (underline and real lists exist in blocks alone).
struct SlackDraft {
    var text: String
    var blocks: String?
}

/// Turns the composer's attributed text into what `chat.postMessage` takes.
enum SlackCompose {
    enum ListKind { case bullet, ordered }
    enum Mark: CaseIterable { case bold, italic, underline, strike }
    struct Marker { let kind: ListKind; let length: Int; let number: Int }

    /// A list line starts with "• " (or a typed "- ") or "3. ". `length` is in UTF-16 units.
    static func marker(_ line: String) -> Marker? {
        if line.hasPrefix("• ") || line.hasPrefix("- ") { return Marker(kind: .bullet, length: 2, number: 0) }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 3, line.dropFirst(digits.count).hasPrefix(". ") {
            return Marker(kind: .ordered, length: digits.count + 2, number: Int(digits) ?? 1)
        }
        return nil
    }

    /// The ranges of the lines of `s` inside `range`, without their terminators; empty lines included.
    static func lines(of s: NSString, in range: NSRange) -> [NSRange] {
        var out: [NSRange] = []
        var loc = range.location
        let limit = NSMaxRange(range)
        while true {
            var start = 0, end = 0, contentsEnd = 0
            s.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
            out.append(NSRange(location: start, length: min(contentsEnd, limit) - start))
            if contentsEnd >= limit || end == contentsEnd { break }
            loc = end
        }
        return out
    }

    static func has(_ mark: Mark, _ attrs: [NSAttributedString.Key: Any]) -> Bool {
        switch mark {
        case .bold: return (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        case .italic: return (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
        case .underline: return (attrs[.underlineStyle] as? Int ?? 0) != 0
        case .strike: return (attrs[.strikethroughStyle] as? Int ?? 0) != 0
        }
    }

    static func draft(from full: NSAttributedString) -> SlackDraft {
        let trimmed = full.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SlackDraft(text: "", blocks: nil) }
        let text = full.attributedSubstring(from: (full.string as NSString).range(of: trimmed))
        let s = text.string as NSString

        var styled = false
        var elements: [[String: Any]] = []
        var fallback: [String] = []
        var section: [[String: Any]] = []
        var sectionLines = 0
        var list: (kind: ListKind, items: [[String: Any]], offset: Int)?

        func flushSection() {
            if !section.isEmpty { elements.append(["type": "rich_text_section", "elements": section]) }
            section = []; sectionLines = 0
        }
        func flushList() {
            guard let l = list else { return }
            var block: [String: Any] = ["type": "rich_text_list", "style": l.kind == .bullet ? "bullet" : "ordered", "elements": l.items]
            if l.offset > 0 { block["offset"] = l.offset }
            elements.append(block)
            list = nil
        }

        for line in lines(of: s, in: NSRange(location: 0, length: s.length)) {
            let m = marker(s.substring(with: line))
            let body = NSRange(location: line.location + (m?.length ?? 0), length: line.length - (m?.length ?? 0))
            let r = runs(text, body)
            styled = styled || r.styled || m != nil
            if let m {
                flushSection()
                if list?.kind != m.kind { flushList(); list = (m.kind, [], max(0, m.number - 1)) }
                list?.items.append(["type": "rich_text_section", "elements": r.leaves])
                fallback.append((m.kind == .bullet ? "• " : "\(m.number). ") + r.markdown)
            } else {
                flushList()
                if sectionLines > 0 { section.append(["type": "text", "text": "\n"]) }
                section.append(contentsOf: r.leaves)
                sectionLines += 1
                fallback.append(r.markdown)
            }
        }
        flushSection(); flushList()

        guard styled, !elements.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: [["type": "rich_text", "elements": elements]]),
              let json = String(data: data, encoding: .utf8) else {
            return SlackDraft(text: trimmed, blocks: nil)
        }
        return SlackDraft(text: fallback.joined(separator: "\n"), blocks: json)
    }

    private static func runs(_ text: NSAttributedString, _ range: NSRange) -> (leaves: [[String: Any]], markdown: String, styled: Bool) {
        guard range.length > 0 else { return ([], "", false) }
        var out: [[String: Any]] = []
        var md = ""
        var styled = false
        text.enumerateAttributes(in: range) { attrs, r, _ in
            let piece = (text.string as NSString).substring(with: r)
            var style: [String: Bool] = [:]
            if has(.bold, attrs) { style["bold"] = true }
            if has(.italic, attrs) { style["italic"] = true }
            if has(.underline, attrs) { style["underline"] = true }
            if has(.strike, attrs) { style["strike"] = true }
            if !style.isEmpty { styled = true }
            out += leaves(piece, style)
            md += markdown(piece, style)
        }
        return (out, md, styled)
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let emojiName = try? NSRegularExpression(pattern: ":([a-z0-9_+\\-]+):")

    /// One run as rich_text leaves: URLs become links and known `:names:` emoji, since Slack
    /// does neither on its own inside blocks.
    private static func leaves(_ piece: String, _ style: [String: Bool]) -> [[String: Any]] {
        let ns = piece as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var marks: [(range: NSRange, leaf: [String: Any])] = []
        for match in detector?.matches(in: piece, range: whole) ?? [] {
            guard let url = match.url, ["http", "https"].contains(url.scheme ?? "") else { continue }
            var leaf: [String: Any] = ["type": "link", "url": url.absoluteString]
            let shown = ns.substring(with: match.range)
            if shown != url.absoluteString { leaf["text"] = shown }
            marks.append((match.range, leaf))
        }
        for match in emojiName?.matches(in: piece, range: whole) ?? [] {
            let name = ns.substring(with: match.range(at: 1))
            guard SlackEmojiTable.names[name] != nil,
                  !marks.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else { continue }
            marks.append((match.range, ["type": "emoji", "name": name]))
        }
        marks.sort { $0.range.location < $1.range.location }
        var out: [[String: Any]] = []
        var cursor = 0
        func text(upTo end: Int) {
            guard end > cursor else { return }
            var leaf: [String: Any] = ["type": "text", "text": ns.substring(with: NSRange(location: cursor, length: end - cursor))]
            if !style.isEmpty { leaf["style"] = style }
            out.append(leaf)
        }
        for mark in marks {
            text(upTo: mark.range.location)
            var leaf = mark.leaf
            if !style.isEmpty, leaf["type"] as? String == "link" { leaf["style"] = style }
            out.append(leaf)
            cursor = NSMaxRange(mark.range)
        }
        text(upTo: ns.length)
        return out
    }

    /// The mrkdwn fallback of one run; markers hug the words, spaces stay outside.
    private static func markdown(_ piece: String, _ style: [String: Bool]) -> String {
        guard !style.isEmpty else { return piece }
        let core = piece.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return piece }
        let lead = String(piece.prefix { $0 == " " || $0 == "\t" })
        let trail = String(piece.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
        var out = core
        if style["strike"] == true { out = "~\(out)~" }
        if style["italic"] == true { out = "_\(out)_" }
        if style["bold"] == true { out = "*\(out)*" }
        return lead + out + trail
    }
}

/// What the toolbar reads from, and acts on, the text view.
@MainActor
final class ComposerModel: ObservableObject {
    weak var view: ComposerTextView?
    @Published var marks: Set<SlackCompose.Mark> = []
    @Published var list: SlackCompose.ListKind?
    @Published var isEmpty = true
    /// What is in the field, in plain text: tells a draft the Mac wrote from one typed over.
    @Published var plain = ""
    @Published var height: CGFloat = 18
    @Published var focused = false
}

/// The editor: bold, italic, underline and strikethrough are real attributes (what you see
/// is what is sent); lists are lines that start with "• " or "1. ". Return sends,
/// Shift-Return breaks the line, Escape cancels. Pasted text comes in plain.
final class ComposerTextView: YieldingTextView {
    var model: ComposerModel?
    var onSend: () -> Void = {}
    var onCancel: () -> Void = {}
    var autofocus = false
    static let size: CGFloat = 13

    static var base: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor(Soot.ink), .paragraphStyle: paragraph]
    }

    func configure() {
        isRichText = true
        importsGraphics = false
        allowsUndo = true
        usesFontPanel = false
        usesRuler = false
        drawsBackground = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        insertionPointColor = NSColor(Soot.lime)
        typingAttributes = Self.base
        setAccessibilityLabel("Reply in thread")
        if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SLACK_DRAFT"] == "1" { loadSample() }
    }

    /// A formatted draft for the capture run, which cannot type.
    private func loadSample() {
        let sample = NSMutableAttributedString(string: "Bold, italic, underlined and struck:\n• first point\n• second point\n1. then this", attributes: Self.base)
        for (word, mark) in [("Bold", SlackCompose.Mark.bold), ("italic", .italic), ("underlined", .underline), ("struck", .strike)] {
            let r = (sample.string as NSString).range(of: word)
            var attrs = Self.base
            Self.set(mark, on: true, in: &attrs)
            sample.setAttributes(attrs, range: r)
        }
        textStorage?.setAttributedString(sample)
    }

    /// Puts a draft in the field as if it had been typed: ⌘Z takes it out again.
    func insertDraft(_ text: String) {
        window?.makeFirstResponder(self)
        insertText(NSAttributedString(string: text, attributes: Self.base),
                   replacementRange: NSRange(location: 0, length: textStorage?.length ?? 0))
    }

    func clear() {
        textStorage?.setAttributedString(NSAttributedString())
        typingAttributes = Self.base
        undoManager?.removeAllActions()
        report()
    }

    // MARK: Formatting

    static func set(_ mark: SlackCompose.Mark, on: Bool, in attrs: inout [NSAttributedString.Key: Any]) {
        switch mark {
        case .bold, .italic:
            let trait: NSFontDescriptor.SymbolicTraits = mark == .bold ? .bold : .italic
            var traits = ((attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []).intersection([.bold, .italic])
            if on { traits.insert(trait) } else { traits.remove(trait) }
            let plain = NSFont.systemFont(ofSize: size)
            attrs[.font] = NSFont(descriptor: plain.fontDescriptor.withSymbolicTraits(traits), size: size) ?? plain
        case .underline:
            attrs[.underlineStyle] = on ? NSUnderlineStyle.single.rawValue : nil
        case .strike:
            attrs[.strikethroughStyle] = on ? NSUnderlineStyle.single.rawValue : nil
        }
    }

    /// With a selection, styles it (off when all of it already has the style); with a bare
    /// caret, styles what is typed next.
    func toggle(_ mark: SlackCompose.Mark) {
        let range = selectedRange()
        if range.length == 0 {
            var attrs = typingAttributes
            Self.set(mark, on: !SlackCompose.has(mark, attrs), in: &attrs)
            typingAttributes = attrs
        } else if let storage = textStorage, shouldChangeText(in: range, replacementString: nil) {
            var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
            storage.enumerateAttributes(in: range) { attrs, r, _ in runs.append((r, attrs)) }
            let all = runs.allSatisfy { SlackCompose.has(mark, $0.1) }
            storage.beginEditing()
            for (r, attrs) in runs {
                var attrs = attrs
                Self.set(mark, on: !all, in: &attrs)
                storage.setAttributes(attrs, range: r)
            }
            storage.endEditing()
            didChangeText()
        }
        report()
    }

    /// Makes the selected lines a list of `kind`, or plain lines again when they all are one.
    func toggleList(_ kind: SlackCompose.ListKind) {
        guard let storage = textStorage else { return }
        let ns = string as NSString
        let selection = selectedRange()
        let block = ns.paragraphRange(for: selection)
        var contents = block
        while contents.length > 0, let last = UnicodeScalar(ns.character(at: NSMaxRange(contents) - 1)), CharacterSet.newlines.contains(last) {
            contents.length -= 1
        }
        let lines = SlackCompose.lines(of: ns, in: contents)
        let markers = lines.map { SlackCompose.marker(ns.substring(with: $0)) }
        let allAre = markers.allSatisfy { $0?.kind == kind }
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: contents))
        for (index, line) in lines.enumerated().reversed() {
            let prefix = allAre ? "" : (kind == .bullet ? "• " : "\(index + 1). ")
            let old = NSRange(location: line.location - contents.location, length: markers[index]?.length ?? 0)
            replacement.replaceCharacters(in: old, with: NSAttributedString(string: prefix, attributes: Self.base))
        }
        guard shouldChangeText(in: contents, replacementString: replacement.string) else { return }
        storage.replaceCharacters(in: contents, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: contents.location + replacement.length, length: 0))
        report()
    }

    /// A line break; inside a list it starts the next item, and on an empty item it leaves the list.
    func breakLine() {
        let ns = string as NSString
        let caret = selectedRange()
        let line = ns.lineRange(for: NSRange(location: caret.location, length: 0))
        let text = ns.substring(with: line).trimmingCharacters(in: .newlines)
        if let m = SlackCompose.marker(text) {
            if (text as NSString).length == m.length {
                insertText("", replacementRange: NSRange(location: line.location, length: m.length))
            } else {
                insertText("\n" + (m.kind == .bullet ? "• " : "\(m.number + 1). "), replacementRange: caret)
            }
        } else {
            insertText("\n", replacementRange: caret)
        }
    }

    // MARK: Keys

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { breakLine() } else { onSend() }
        case #selector(insertLineBreak(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)):
            breakLine()
        case #selector(cancelOperation(_:)):
            onCancel()
        default:
            super.doCommand(by: selector)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (flags, key) {
        case ([.command], "b"): toggle(.bold); return true
        case ([.command], "i"): toggle(.italic); return true
        case ([.command], "u"): toggle(.underline); return true
        case ([.command, .shift], "x"): toggle(.strike); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    // MARK: State

    override func didChangeText() {
        super.didChangeText()
        report()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting { report() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        report()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { report(focused: true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { report(focused: false) }
        return ok
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        report()
        if autofocus, window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The ink is a per-appearance colour: re-resolve it on what is already typed.
        if let storage = textStorage, storage.length > 0 {
            storage.addAttribute(.foregroundColor, value: NSColor(Soot.ink), range: NSRange(location: 0, length: storage.length))
        }
        typingAttributes[.foregroundColor] = NSColor(Soot.ink)
        insertionPointColor = NSColor(Soot.lime)
    }

    /// Publishes what the toolbar shows: the styles at the caret, the list the line is in,
    /// whether anything is typed, and the height the text needs.
    private func report(focused: Bool? = nil) {
        guard let model, let layoutManager, let textContainer else { return }
        let range = selectedRange()
        let ns = string as NSString
        var attrs = typingAttributes
        if range.length > 0, let storage = textStorage, range.location < storage.length {
            attrs = storage.attributes(at: range.location, effectiveRange: nil)
        }
        let marks = Set(SlackCompose.Mark.allCases.filter { SlackCompose.has($0, attrs) })
        let line = ns.lineRange(for: NSRange(location: min(range.location, ns.length), length: 0))
        let list = SlackCompose.marker(ns.substring(with: line))?.kind
        layoutManager.ensureLayout(for: textContainer)
        let height = max(18, ceil(layoutManager.usedRect(for: textContainer).height))
        let empty = ns.length == 0
        DispatchQueue.main.async {
            if model.marks != marks { model.marks = marks }
            if model.list != list { model.list = list }
            if model.isEmpty != empty { model.isEmpty = empty }
            if model.plain != self.string { model.plain = self.string }
            if abs(model.height - height) > 0.5 { model.height = height }
            if let focused, model.focused != focused { model.focused = focused }
        }
    }
}

private struct ComposerField: NSViewRepresentable {
    let model: ComposerModel
    let autofocus: Bool
    let enabled: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        let view = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
        view.minSize = NSSize(width: 0, height: 18)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.model = model
        view.autofocus = autofocus
        view.configure()
        scroll.documentView = view
        model.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? ComposerTextView else { return }
        view.onSend = onSend
        view.onCancel = onCancel
        view.isEditable = enabled
    }
}

/// The box a reply is written in: the text on top, growing to seven lines; under it the
/// formatting strip (bold, italic, underline, strikethrough, bullets, numbers) and Send.
struct ReplyComposer: View {
    let sending: Bool
    var autofocus = true
    var fill: Color = Soot.ground
    /// Posts the draft; `true` clears the box.
    let send: (SlackDraft) async -> Bool
    let cancel: () -> Void
    /// Writes a reply from the thread, on the Mac; nil when no draft is offered here.
    var draft: (() async -> String?)? = nil
    @StateObject private var model = ComposerModel()
    /// The Mac is writing a draft.
    @State private var drafting = false
    /// The draft the Mac wrote, while the field still holds it untouched.
    @State private var drafted: String?
    private var isDraft: Bool { drafted != nil && model.plain == drafted }

    private static let marks: [(SlackCompose.Mark, String, String)] = [
        (.bold, "bold", "Bold (⌘B)"), (.italic, "italic", "Italic (⌘I)"),
        (.underline, "underline", "Underline (⌘U)"), (.strike, "strikethrough", "Strikethrough (⇧⌘X)"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if drafting {
                    SummarisingLine(label: "Writing a draft").frame(height: 18)
                } else if model.isEmpty {
                    Text("Reply in thread").font(.system(size: 13)).foregroundStyle(Soot.muted)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                ComposerField(model: model, autofocus: autofocus, enabled: !sending, onSend: submit, onCancel: {
                    model.view?.clear()
                    cancel()
                })
                .frame(height: min(max(model.height, 18), 132))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            HStack(spacing: 2) {
                ForEach(Self.marks, id: \.1) { mark, symbol, label in
                    tool(symbol, label, on: model.marks.contains(mark)) { model.view?.toggle(mark) }
                }
                Rectangle().fill(Soot.line).frame(width: 1, height: 16).padding(.horizontal, 5)
                tool("list.bullet", "Bulleted list", on: model.list == .bullet) { model.view?.toggleList(.bullet) }
                tool("list.number", "Numbered list", on: model.list == .ordered) { model.view?.toggleList(.ordered) }
                Spacer(minLength: 8)
                if isDraft {
                    // Until the first change the text is the Mac's, and says so; then it is the user's.
                    HStack(spacing: 4) {
                        GeneratedMark(size: 10)
                        Text("Draft").font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
                    }
                    .padding(.trailing, 6)
                    .transition(.opacity)
                } else if draft != nil, model.isEmpty, !drafting {
                    tool("sparkles", "Draft a reply from the thread", on: false, action: writeDraft)
                        .padding(.trailing, 2)
                        .transition(.opacity)
                }
                Button(action: submit) {
                    Text("Send").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.isEmpty || sending ? Soot.muted : Soot.limeInk)
                        .padding(.horizontal, 12).frame(height: 28)
                }
                .buttonStyle(ChipButton(on: !(model.isEmpty || sending), edge: false))
                .disabled(model.isEmpty || sending)
                .help("Send (Return). Shift-Return for a new line.")
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .background(fill, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
        .overlay(RoundedRectangle(cornerRadius: Soot.fieldRadius)
            .strokeBorder(model.focused ? Soot.lime : Soot.edge, lineWidth: model.focused ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: Soot.fieldRadius))
        .motion(Motion.quick, fade: true, value: model.focused)
        .onTapGesture { if let view = model.view { view.window?.makeFirstResponder(view) } }
        .opacity(sending ? 0.6 : 1)
        .padding(.top, 4)
    }

    private func tool(_ symbol: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: on ? .bold : .medium)).frame(width: 28, height: 26)
        }
        .buttonStyle(IconButton(fill: on ? Soot.ink.opacity(0.14) : nil, radius: 6))
        .disabled(sending)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Asks for a draft and puts it in the field, unless the user has started to type meanwhile.
    private func writeDraft() {
        guard let draft, !drafting else { return }
        Motion.run(Motion.ui, fade: true) { drafting = true }
        Task {
            let text = await draft()
            Motion.run(Motion.ui, fade: true) { drafting = false }
            guard let text, model.isEmpty, let view = model.view else { return }
            drafted = text
            view.insertDraft(text)
        }
    }

    private func submit() {
        guard !sending, let view = model.view else { return }
        let draft = SlackCompose.draft(from: view.attributedString())
        guard !draft.text.isEmpty else { return }
        Task { if await send(draft) { view.clear() } }
    }
}
