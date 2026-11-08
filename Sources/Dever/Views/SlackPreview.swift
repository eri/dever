import AppKit
import PDFKit
import Quartz
import SwiftUI

/// A Slack file read here, not in Slack, over a dimmed page: a click outside or Escape closes.
/// The original is downloaded once with the token into the purgeable cache; "Save…" copies it
/// where you choose. Pictures, PDFs and anything Quick Look knows.
struct FileLightbox: View {
    let file: SlackFile
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .transition(.opacity)
                .accessibilityHidden(true)
            FilePreviewSheet(file: file, close: close)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.45), radius: 30, y: 10)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
        }
        .accessibilityAddTraits(.isModal)
    }
}

struct FilePreviewSheet: View {
    @EnvironmentObject var app: AppState
    let file: SlackFile
    let close: () -> Void
    @State private var local: URL?
    @State private var error: String?

    private var detail: String {
        [file.filetype?.uppercased(), file.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let screen = NSApp.keyWindow?.frame.size ?? NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: file.isImage ? "photo" : "doc").font(.system(size: 13)).foregroundStyle(Soot.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.displayName).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(Soot.muted) }
                }
                Spacer()
                if let local {
                    Button { save(local) } label: { Text("Save…") }
                        .buttonStyle(.plain).handCursor().font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
                        .modifier(FocusOutline(radius: 4))
                        .help("Save a copy of the file")
                }
                if let url = file.permalink.flatMap(URL.init(string:)) {
                    Link(destination: url) { HStack(spacing: 4) { Text("Open in Slack"); Image(systemName: "arrow.up.right") } }
                        .handCursor().font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.lime)
                }
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.ink)
                        .frame(width: 30, height: 30).background(Soot.surface, in: Circle())
                }
                .buttonStyle(.plain).handCursor().modifier(FocusOutline(radius: 15))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close the preview")
            }
            .padding(.horizontal, 20).frame(height: 60)
            Rectangle().fill(Soot.line).frame(height: 1)
            Group {
                if let local {
                    if file.mimetype?.hasPrefix("image/") == true {
                        ImagePreview(url: local, name: file.displayName)
                    } else if file.mimetype == "application/pdf" || file.filetype == "pdf" {
                        PDFPreview(url: local)
                    } else {
                        QuickLookPreview(url: local)
                    }
                } else if let error {
                    VStack(spacing: 6) {
                        Text("Couldn't load the file.").font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink)
                        Text(error).font(.system(size: 12)).foregroundStyle(Soot.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack { WaitingLine().frame(width: 160) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement().accessibilityLabel("Loading the file")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.35))
        }
        .frame(width: min(1280, screen.width * 0.86), height: min(900, screen.height * 0.88))
        .background(Soot.ground)
        .task(id: file.id) {
            do { local = try await app.withSlack { try await SlackMediaCache.shared.localFile(for: file, client: $0) } }
            catch { self.error = error.localizedDescription }
        }
    }

    private func save(_ local: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name ?? local.lastPathComponent
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let target = panel.url else { return }
            try? FileManager.default.removeItem(at: target)
            do { try FileManager.default.copyItem(at: local, to: target) } catch { app.report(error) }
        }
    }
}

/// Message text as a native label: links get the pointing hand and open on click, text
/// selects, and the field measures its own height for the width SwiftUI proposes.
struct RichTextLabel: NSViewRepresentable {
    let text: AttributedString
    var size: CGFloat = 14
    var color: Color = Soot.ink
    var lineLimit: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    /// A read-only text view: unlike a text field it honours the link colour and keeps its
    /// attributes while selecting; links show the pointing hand and open on click.
    final class LabelView: NSTextView {
        override var acceptsFirstResponder: Bool { true }
        override func resetCursorRects() {
            super.resetCursorRects()
            guard let lm = layoutManager, let tc = textContainer, let storage = textStorage else { return }
            storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard value != nil else { return }
                let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                lm.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { rect, _ in
                    self.addCursorRect(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y), cursor: .pointingHand)
                }
            }
        }
    }

    func makeNSView(context: Context) -> LabelView {
        let view = LabelView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isRichText = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: LabelView, context: Context) {
        view.linkTextAttributes = [.foregroundColor: NSColor(Soot.lime), .cursor: NSCursor.pointingHand]
        view.textStorage?.setAttributedString(Self.nsAttributed(text, size: size, color: color))
        view.textContainer?.maximumNumberOfLines = lineLimit
        view.textContainer?.lineBreakMode = lineLimit > 0 ? .byTruncatingTail : .byWordWrapping
        view.window?.invalidateCursorRects(for: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: LabelView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 320, 40)
        guard let container = view.textContainer, let lm = view.layoutManager else { return nil }
        let live = container.containerSize
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: container)
        let height = lm.usedRect(for: container).height
        // SwiftUI also asks trial sizes: put the text back at the view's own width, or a
        // label whose frame then does not change stays wrapped at the trial width.
        container.containerSize = view.frame.width > 0 ? NSSize(width: view.frame.width, height: live.height) : live
        return CGSize(width: width, height: ceil(height))
    }

    /// SwiftUI's presentation intents and colours turned into AppKit fonts and attributes.
    /// The SF Symbol "link" as an inline attachment, lime, sized to the text.
    static func linkGlyph(size: CGFloat) -> NSTextAttachment? {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.82, weight: .semibold)
            .applying(.init(paletteColors: [NSColor(Soot.lime)]))
        guard let image = NSImage(systemSymbolName: "link", accessibilityDescription: "Link")?.withSymbolConfiguration(config) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -1, width: image.size.width, height: image.size.height)
        return attachment
    }

    static func nsAttributed(_ text: AttributedString, size: CGFloat, color: Color) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.lineBreakMode = .byWordWrapping
        for run in text.runs {
            let piece = String(text[run.range].characters)
            var attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraph, .foregroundColor: NSColor(color)]
            let intent = run.inlinePresentationIntent ?? []
            var font = NSFont.systemFont(ofSize: size)
            if intent.contains(.code) {
                font = NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)
                attrs[.backgroundColor] = NSColor(Soot.ink).withAlphaComponent(0.08)
            } else if intent.contains(.stronglyEmphasized) && intent.contains(.emphasized) {
                font = NSFontManager.shared.convert(NSFont.boldSystemFont(ofSize: size), toHaveTrait: .italicFontMask)
            } else if intent.contains(.stronglyEmphasized) {
                font = NSFont.boldSystemFont(ofSize: size)
            } else if intent.contains(.emphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            attrs[.font] = font
            if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let fg = run.foregroundColor { attrs[.foregroundColor] = NSColor(fg) }
            if let bg = run.backgroundColor { attrs[.backgroundColor] = NSColor(bg) }
            if let link = run.link {
                attrs[.link] = link
                attrs[.foregroundColor] = NSColor(Soot.lime)
                attrs[.underlineStyle] = 0
                attrs[.backgroundColor] = nil
                attrs[.cursor] = NSCursor.pointingHand
                // A bare URL (a chip) leads with a small link glyph instead of a highlight.
                if piece.hasPrefix("\u{2009}"), let glyph = linkGlyph(size: size) {
                    // A faint wash of the link colour sets the URL apart without shouting.
                    // The chip wraps as one block: narrow no-break spaces around it, no-break hyphens
                    // and word joiners inside, so a line never ends on "pr-4714-".
                    attrs[.backgroundColor] = NSColor(Soot.lime).withAlphaComponent(0.09)
                    out.append(NSAttributedString(string: "\u{202F}", attributes: attrs))
                    let icon = NSMutableAttributedString(attachment: glyph)
                    icon.addAttributes([.link: link, .cursor: NSCursor.pointingHand, .backgroundColor: attrs[.backgroundColor]!],
                                       range: NSRange(location: 0, length: icon.length))
                    out.append(icon)
                    out.append(NSAttributedString(string: "\u{202F}", attributes: attrs))
                    let label = piece.trimmingCharacters(in: CharacterSet(charactersIn: "\u{2009}"))
                        .replacingOccurrences(of: "-", with: "\u{2011}")
                        .replacingOccurrences(of: "/", with: "/\u{2060}")
                        .replacingOccurrences(of: ".", with: ".\u{2060}")
                        .replacingOccurrences(of: " ", with: "\u{00A0}")
                    attrs[.font] = NSFont.systemFont(ofSize: size, weight: .medium)
                    out.append(NSAttributedString(string: label + "\u{202F}", attributes: attrs))
                    continue
                }
            }
            out.append(NSAttributedString(string: piece, attributes: attrs))
        }
        return out
    }
}

/// A cursor for the area of a view, through AppKit's cursor rects: reliable where
/// pushing cursors on hover is not. Clicks pass through.
struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor

    final class CursorView: NSView {
        var cursor: NSCursor = .arrow
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
    }

    func makeNSView(context: Context) -> CursorView {
        let view = CursorView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ view: CursorView, context: Context) {
        view.cursor = cursor
        view.window?.invalidateCursorRects(for: view)
    }
}

/// Sets the enclosing scroll view to thin overlay scrollers that hide when idle.
struct OverlayScrollers: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var view: NSView? = superview
            while let v = view, !(v is NSScrollView) { view = v.superview }
            if let scroll = view as? NSScrollView {
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
                scroll.verticalScroller?.controlSize = .small
            }
        }
    }
    func makeNSView(context: Context) -> Probe { Probe(frame: .zero) }
    func updateNSView(_ view: Probe, context: Context) {}
}

/// A picture at its natural size, scaled down to fit; decoded off the main thread.
struct ImagePreview: View {
    let url: URL
    let name: String
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: min(geo.size.width - 40, image.size.width), maxHeight: min(geo.size.height - 40, image.size.height))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel(name)
                } else {
                    WaitingLine().frame(width: 160)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: url) {
            let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
            image = loaded
        }
    }
}

/// PDFKit for documents: pages, zoom and text selection.
struct PDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

/// Quick Look's own view, as it draws any file type the system knows.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url { view.previewItem = url as QLPreviewItem }
    }
}
