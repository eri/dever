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
                    Button { save(local) } label: { Label("Save", systemImage: "square.and.arrow.down") }
                        .buttonStyle(ToolbarButton())
                        .help("Save a copy of the file")
                }
                if let url = file.permalink.flatMap(URL.init(string:)) {
                    Menu {
                        Link("Open in Slack", destination: url)
                        Button("Copy link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .menuStyle(.button)
                    .buttonStyle(MenuTriggerButton(edge: false))
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More: open in Slack, copy the link")
                    .accessibilityLabel("More actions")
                }
                GlyphButton(symbol: "xmark", label: "Close the preview", size: 30, action: close)
                    .keyboardShortcut(.cancelAction)
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
    final class LabelView: YieldingTextView {
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
    static func linkGlyph(size: CGFloat, symbol: String = "link") -> NSTextAttachment? {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.82, weight: .semibold)
            .applying(.init(paletteColors: [NSColor(Soot.lime)]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol == "link" ? "Link" : "Slack message")?
            .withSymbolConfiguration(config) else { return nil }
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
            if run.appKit.underlineStyle != nil { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let fg = run.foregroundColor { attrs[.foregroundColor] = NSColor(fg) }
            if let bg = run.backgroundColor { attrs[.backgroundColor] = NSColor(bg) }
            if let link = run.link {
                attrs[.link] = link
                attrs[.foregroundColor] = NSColor(Soot.lime)
                attrs[.underlineStyle] = 0
                attrs[.backgroundColor] = nil
                attrs[.cursor] = NSCursor.pointingHand
                // A bare URL (a chip) leads with a small link glyph instead of a highlight.
                let isMessage = piece.hasPrefix("\u{200A}")
                if piece.hasPrefix("\u{2009}") || isMessage, let glyph = linkGlyph(size: size, symbol: isMessage ? "bubble.left.fill" : "link") {
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
                    let label = piece.trimmingCharacters(in: CharacterSet(charactersIn: "\u{2009}\u{200A}"))
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

/// A text view that leaves the cursor alone where something else is drawn over it (a pill
/// floating over a message, a hover toolbar): without this its I-beam shows on the button.
/// Every `NSTextView` of the app inherits from it.
class YieldingTextView: NSTextView {
    private func covered(_ event: NSEvent) -> Bool {
        guard let root = window?.contentView else { return false }
        let point = root.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        guard let hit = root.hitTest(point) else { return true }
        return !(hit === self || hit.isDescendant(of: self))
    }
    override func mouseMoved(with event: NSEvent) { if !covered(event) { super.mouseMoved(with: event) } }
    override func cursorUpdate(with event: NSEvent) { if !covered(event) { super.cursorUpdate(with: event) } }
}

/// A cursor for the area of a view, through AppKit's cursor rects: reliable where
/// pushing cursors on hover is not. Clicks pass through.
///
/// Areas drawn over others (a card floating over a list) still receive the moves of the
/// areas under them, so each claim waits a little longer the higher its priority: the area
/// in front sets the cursor last. The priority comes from `cursorPriority(_:)`.
struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor
    var priority: Int? = nil

    final class CursorView: NSView {
        var cursor: NSCursor = .arrow
        var priority = 0
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }

        // Selectable text under a floating button sets the I-beam on every mouse move, past
        // the cursor rect. The area answers each move after it, so its cursor has the last word.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                           owner: self))
        }
        override func mouseEntered(with event: NSEvent) { claim() }
        override func mouseMoved(with event: NSEvent) { claim() }
        private func claim() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012 * Double(priority)) { [weak self] in
                guard let self, let window = self.window,
                      self.bounds.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil)) else { return }
                self.cursor.set()
            }
        }
    }

    func makeNSView(context: Context) -> CursorView {
        let view = CursorView()
        view.cursor = cursor
        view.priority = priority ?? context.environment.cursorPriority
        return view
    }

    func updateNSView(_ view: CursorView, context: Context) {
        view.cursor = cursor
        view.priority = priority ?? context.environment.cursorPriority
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
    /// 1 is the picture's own pixels; nil fits it to the window.
    @State private var zoom: CGFloat?
    @State private var pinchBase: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let steps: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]

    var body: some View {
        GeometryReader { geo in
            let fit = image.map { min(1, min((geo.size.width - 40) / $0.size.width, (geo.size.height - 40) / $0.size.height)) } ?? 1
            let scale = zoom ?? fit
            ZStack(alignment: .bottom) {
                if let image {
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().interpolation(.high)
                            .frame(width: size.width, height: size.height)
                            .clipShape(RoundedRectangle(cornerRadius: scale == fit ? 6 : 0))
                            .accessibilityLabel(name)
                            // Centred while it fits; scrolls once it is larger than the window.
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height - 56)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onTapGesture(count: 2) { set(zoom == nil ? 1 : nil) }
                    .gesture(MagnifyGesture().onChanged { value in
                        if pinchBase == nil { pinchBase = scale }
                        zoom = min(8, max(0.1, (pinchBase ?? scale) * value.magnification))
                    }.onEnded { _ in pinchBase = nil })
                } else {
                    WaitingLine().frame(width: 160).frame(width: geo.size.width, height: geo.size.height)
                }
                if image != nil { zoomBar(scale: scale, fit: fit).padding(.bottom, 14) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: url) {
            zoom = nil
            let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
            image = loaded
        }
    }

    /// Zoom out, the current level (click to fit), zoom in: a small floating strip.
    private func zoomBar(scale: CGFloat, fit: CGFloat) -> some View {
        HStack(spacing: 2) {
            zoomButton("minus", help: "Zoom out") { step(-1, scale: scale) }
                .disabled(scale <= Self.steps.first!)
            Button { set(zoom == nil ? 1 : nil) } label: {
                Text("\(Int((scale * 100).rounded())) %").monospacedDigit()
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 52, minHeight: 28)
            }
            .buttonStyle(IconButton(fill: nil))
            .help(zoom == nil ? "Actual size" : "Fit to window")
            .accessibilityLabel("Zoom \(Int((scale * 100).rounded())) percent")
            .accessibilityHint(zoom == nil ? "Shows the picture at actual size" : "Fits the picture to the window")
            zoomButton("plus", help: "Zoom in") { step(1, scale: scale) }
                .disabled(scale >= Self.steps.last!)
        }
        .padding(3)
        .background(Soot.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Soot.line))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }

    private func zoomButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        GlyphButton(symbol: symbol, label: help, fill: nil, action: action)
    }

    private func step(_ direction: Int, scale: CGFloat) {
        let next = direction > 0 ? Self.steps.first { $0 > scale + 0.001 } : Self.steps.last { $0 < scale - 0.001 }
        set(next ?? scale)
    }

    private func set(_ value: CGFloat?) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { zoom = value }
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

private struct CursorPriorityKey: EnvironmentKey { static let defaultValue = 0 }

extension EnvironmentValues {
    /// How late the cursor areas inside a view claim the cursor: 0 for the page, more for
    /// what floats over it.
    var cursorPriority: Int {
        get { self[CursorPriorityKey.self] }
        set { self[CursorPriorityKey.self] = newValue }
    }
}

extension View {
    /// Marks a floating surface: its cursor areas win over those of the page under it.
    func cursorPriority(_ priority: Int) -> some View { environment(\.cursorPriority, priority) }
}
