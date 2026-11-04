import Foundation

/// One block of a Markdown document, ready for a SwiftUI `Text` or a dedicated view.
/// Foundation parses the Markdown (headings, lists, quotes, code, links, images, emphasis);
/// this groups its runs into blocks, which `Text` alone would flatten into one paragraph.
struct MarkdownBlock: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case paragraph
        case heading(Int)
        case code(language: String?)
        case quote
        /// `ordinal` is nil for a bullet; `checked` is set for a task-list item.
        case listItem(ordinal: Int?, depth: Int, checked: Bool?)
        case image(URL, alt: String)
        case rule
        case tableRow(header: Bool)
    }
    let id: Int
    let kind: Kind
    let text: AttributedString
}

enum MarkdownBlocks {
    /// Parses `markdown` into blocks. Safe to call off the main thread.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let (source, checks) = liftTaskItems(markdown)
        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: true, interpretedSyntax: .full,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return [MarkdownBlock(id: 0, kind: .paragraph, text: AttributedString(markdown))]
        }
        var blocks: [MarkdownBlock] = []
        var current: (identity: Int, kind: MarkdownBlock.Kind, text: AttributedString)?
        var taskIndex = 0

        func flush() {
            guard let c = current else { return }
            var text = c.text
            // Code blocks keep a trailing newline from the fence; paragraphs never need one.
            while text.characters.last?.isNewline == true { text.removeSubrange(text.index(beforeCharacter: text.endIndex)..<text.endIndex) }
            blocks.append(MarkdownBlock(id: blocks.count, kind: c.kind, text: text))
            current = nil
        }

        for run in parsed.runs {
            var piece = AttributedString(parsed[run.range])
            // Images arrive as a run carrying `imageURL`; they are blocks of their own.
            if let url = run.imageURL {
                flush()
                blocks.append(MarkdownBlock(id: blocks.count, kind: .image(url, alt: String(piece.characters)), text: AttributedString()))
                continue
            }
            piece.presentationIntent = nil
            guard let intent = run.presentationIntent else {
                if current == nil { current = (-1, .paragraph, AttributedString()) }
                current?.text.append(piece)
                continue
            }
            let (identity, kind) = classify(intent)
            if current?.identity != identity {
                flush()
                var k = kind
                if case .listItem(let ordinal, let depth, _) = kind, taskIndex < checks.count,
                   let marker = taskMarker(in: piece) {
                    k = .listItem(ordinal: ordinal, depth: depth, checked: checks[taskIndex])
                    taskIndex += 1
                    piece.removeSubrange(piece.startIndex..<marker)
                }
                current = (identity, k, AttributedString())
            }
            if case .code = kind { piece.inlinePresentationIntent = nil }
            current?.text.append(piece)
        }
        flush()
        return blocks
    }

    /// The innermost block of a run (its identity) and what it is, given its enclosing lists and quotes.
    private static func classify(_ intent: PresentationIntent) -> (Int, MarkdownBlock.Kind) {
        var depth = 0
        var ordinal: Int?
        var quoted = false
        var header = false
        var leaf: (Int, MarkdownBlock.Kind)?
        for component in intent.components {
            switch component.kind {
            case .paragraph:
                if leaf == nil { leaf = (component.identity, .paragraph) }
            case .header(let level):
                if leaf == nil { leaf = (component.identity, .heading(level)) }
            case .codeBlock(let lang):
                if leaf == nil { leaf = (component.identity, .code(language: lang)) }
            case .thematicBreak:
                if leaf == nil { leaf = (component.identity, .rule) }
            case .listItem(let n):
                depth += 1
                if ordinal == nil { ordinal = n }
            case .blockQuote:
                quoted = true
            case .tableHeaderRow:
                header = true
            case .tableRow:
                if leaf == nil { leaf = (component.identity, .tableRow(header: false)) }
            case .tableCell:
                break
            default:
                break
            }
        }
        guard let (identity, kind) = leaf else { return (intent.hashValue, .paragraph) }
        if case .tableRow = kind { return (identity, .tableRow(header: header)) }
        if header { return (identity, .tableRow(header: true)) }
        if depth > 0 {
            // Every item carries an ordinal, bullets included: the innermost list's kind decides.
            let ordered = intent.components.first {
                if case .orderedList = $0.kind { return true }
                if case .unorderedList = $0.kind { return true }
                return false
            }.map { if case .orderedList = $0.kind { true } else { false } } ?? false
            return (identity, .listItem(ordinal: ordered ? ordinal : nil, depth: depth, checked: nil))
        }
        if quoted, case .paragraph = kind { return (identity, .quote) }
        return (identity, kind)
    }

    /// Foundation does not know task lists: `- [ ] text` becomes `- ☐ text` with the checks
    /// remembered in order, and the marker is removed again once the item is classified.
    private static func liftTaskItems(_ s: String) -> (String, [Bool]) {
        var checks: [Bool] = []
        var out: [String] = []
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            if let m = line.range(of: #"^\s*(?:[-*+]|\d+\.)\s+\[( |x|X)\]\s"#, options: .regularExpression) {
                let checked = line[m].contains("x") || line[m].contains("X")
                checks.append(checked)
                let head = line[m].replacingOccurrences(of: #"\[( |x|X)\]\s"#, with: "", options: .regularExpression)
                out.append(head + taskToken + " " + line[m.upperBound...])
            } else {
                out.append(String(line))
            }
        }
        return (out.joined(separator: "\n"), checks)
    }

    private static let taskToken = "\u{2610}"

    private static func taskMarker(in piece: AttributedString) -> AttributedString.Index? {
        let chars = piece.characters
        guard let first = chars.first, String(first) == taskToken else { return nil }
        var i = chars.index(after: chars.startIndex)
        if i < chars.endIndex, chars[i] == " " { i = chars.index(after: i) }
        return i
    }
}
